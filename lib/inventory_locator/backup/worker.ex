defmodule InventoryLocator.Backup.Worker do
  @moduledoc false
  alias InventoryLocator.Backup.LocalStorage
  alias InventoryLocator.Backup.MaintenanceMode
  alias InventoryLocator.Repo

  require Logger

  @base_prefix "inventory-locator/"
  @daily_prefix "#{@base_prefix}daily/"
  @weekly_prefix "#{@base_prefix}weekly/"
  @photos_prefix "#{@base_prefix}photos/"
  @pre_restore_prefix "#{@base_prefix}pre-restore/"

  @type backup_result :: {:ok, String.t()} | {:error, term()}
  @type restore_result :: :ok | {:error, term()}

  @spec run_daily() :: backup_result()
  def run_daily do
    Logger.info("Starting daily backup")
    timestamp = format_timestamp(DateTime.utc_now())
    backup_key = "#{@daily_prefix}#{timestamp}.sql.gz"

    with {:ok, dump_path} <- create_database_dump(),
         :ok <- LocalStorage.upload(dump_path, backup_key),
         :ok <- File.rm(dump_path),
         {:ok, _count} <- sync_photos() do
      Logger.info("Daily backup completed: #{backup_key}")
      {:ok, backup_key}
    else
      {:error, reason} = error ->
        Logger.error("Daily backup failed: #{inspect(reason)}")
        error
    end
  end

  @spec run_weekly() :: backup_result()
  def run_weekly do
    Logger.info("Starting weekly backup")
    timestamp = format_timestamp(DateTime.utc_now())
    backup_key = "#{@weekly_prefix}#{timestamp}.sql.gz"

    with {:ok, dump_path} <- create_database_dump(),
         :ok <- LocalStorage.upload(dump_path, backup_key),
         :ok <- File.rm(dump_path) do
      Logger.info("Weekly backup completed: #{backup_key}")
      {:ok, backup_key}
    else
      {:error, reason} = error ->
        Logger.error("Weekly backup failed: #{inspect(reason)}")
        error
    end
  end

  @spec restore(String.t()) :: restore_result()
  def restore(backup_key) do
    Logger.warning("Starting full restore from: #{backup_key}")

    with :ok <- MaintenanceMode.activate("Restore in progress"),
         {:ok, _pre_restore_key} <- create_pre_restore_backup(),
         {:ok, local_path} <- download_backup(backup_key),
         :ok <- restore_database(local_path),
         :ok <- File.rm(local_path),
         :ok <- restore_photos() do
      Logger.info("Full restore completed successfully")
      MaintenanceMode.deactivate()
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Restore failed: #{inspect(reason)}")
        MaintenanceMode.deactivate()
        error
    end
  end

  @spec cleanup_old_backups(integer(), integer()) :: :ok
  def cleanup_old_backups(daily_retention_days, weekly_retention_weeks) do
    daily_cutoff = DateTime.add(DateTime.utc_now(), -daily_retention_days, :day)
    weekly_cutoff = DateTime.add(DateTime.utc_now(), -weekly_retention_weeks * 7, :day)

    cleanup_prefix(@daily_prefix, daily_cutoff)
    cleanup_prefix(@weekly_prefix, weekly_cutoff)

    :ok
  end

  @spec list_daily_backups() :: {:ok, [LocalStorage.object_info()]} | {:error, term()}
  def list_daily_backups do
    LocalStorage.list_objects(@daily_prefix)
  end

  @spec list_weekly_backups() :: {:ok, [LocalStorage.object_info()]} | {:error, term()}
  def list_weekly_backups do
    LocalStorage.list_objects(@weekly_prefix)
  end

  @spec sync_photos() :: {:ok, integer()} | {:error, term()}
  def sync_photos do
    uploads_dir = uploads_directory()

    if File.dir?(uploads_dir) do
      LocalStorage.sync_directory(uploads_dir, @photos_prefix)
    else
      {:ok, 0}
    end
  end

  # Database operations using safe argument passing (no shell injection)

  @spec create_database_dump() :: {:ok, String.t()} | {:error, term()}
  defp create_database_dump do
    {host, port, user, password, database} = get_db_config()
    sql_path = Path.join(System.tmp_dir!(), "backup_#{System.unique_integer([:positive])}.sql")
    gz_path = "#{sql_path}.gz"

    Logger.debug("Running pg_dump")

    pg_args = ["-h", host, "-p", to_string(port), "-U", user, "-d", database, "--no-owner", "--no-acl", "-f", sql_path]
    env = if password, do: [{"PGPASSWORD", password}], else: []

    case System.cmd("pg_dump", pg_args, env: env, stderr_to_stdout: true) do
      {_output, 0} ->
        case System.cmd("gzip", [sql_path], stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, gz_path}

          {output, exit_code} ->
            File.rm(sql_path)
            Logger.error("gzip failed with exit code #{exit_code}: #{output}")
            {:error, {:gzip_failed, exit_code}}
        end

      {output, exit_code} ->
        File.rm(sql_path)
        Logger.error("pg_dump failed with exit code #{exit_code}: #{output}")
        {:error, {:pg_dump_failed, exit_code}}
    end
  end

  @spec restore_database(String.t()) :: :ok | {:error, term()}
  defp restore_database(gz_path) do
    {host, port, user, password, database} = get_db_config()
    sql_path = String.replace_suffix(gz_path, ".gz", "")
    env = if password, do: [{"PGPASSWORD", password}], else: []

    # Decompress the backup
    case_result =
      case System.cmd("gunzip", ["-k", gz_path], stderr_to_stdout: true) do
        {_output, 0} ->
          :ok

        {output, exit_code} ->
          Logger.error("gunzip failed with exit code #{exit_code}: #{output}")
          {:error, {:gunzip_failed, exit_code}}
      end

    case case_result do
      :ok ->
        Logger.info("Dropping database #{database}")
        drop_args = ["-h", host, "-p", to_string(port), "-U", user, "--if-exists", database]

        case System.cmd("dropdb", drop_args, env: env, stderr_to_stdout: true) do
          {_, 0} -> :ok
          {output, code} -> Logger.warning("dropdb returned #{code}: #{output}")
        end

        Logger.info("Creating database #{database}")
        create_args = ["-h", host, "-p", to_string(port), "-U", user, database]

        case System.cmd("createdb", create_args, env: env, stderr_to_stdout: true) do
          {_, 0} ->
            Logger.info("Restoring database from backup")
            psql_args = ["-h", host, "-p", to_string(port), "-U", user, "-d", database, "-f", sql_path]

            result =
              case System.cmd("psql", psql_args, env: env, stderr_to_stdout: true) do
                {_, 0} -> :ok
                {output, code} -> {:error, {:psql_failed, code, output}}
              end

            File.rm(sql_path)
            result

          {output, code} ->
            File.rm(sql_path)
            {:error, {:createdb_failed, code, output}}
        end

      error ->
        error
    end
  end

  @spec get_db_config() :: {String.t(), integer(), String.t(), String.t() | nil, String.t()}
  defp get_db_config do
    config = Repo.config()

    case config[:url] do
      nil ->
        {
          config[:hostname] || "localhost",
          config[:port] || 5432,
          config[:username],
          config[:password],
          config[:database]
        }

      url ->
        parse_database_url(url)
    end
  end

  @spec parse_database_url(String.t()) :: {String.t(), integer(), String.t(), String.t() | nil, String.t()}
  defp parse_database_url(url) do
    uri = URI.parse(url)
    userinfo = uri.userinfo || ""

    {user, password} =
      case String.split(userinfo, ":", parts: 2) do
        [u, p] -> {u, p}
        [u] -> {u, nil}
        [] -> {nil, nil}
      end

    database = String.trim_leading(uri.path || "", "/")

    {
      uri.host || "localhost",
      uri.port || 5432,
      user,
      password,
      database
    }
  end

  @spec download_backup(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp download_backup(backup_key) do
    tmp_path = Path.join(System.tmp_dir!(), "restore_#{System.unique_integer([:positive])}.sql.gz")

    case LocalStorage.download(backup_key, tmp_path) do
      :ok -> {:ok, tmp_path}
      error -> error
    end
  end

  @spec create_pre_restore_backup() :: {:ok, String.t()} | {:error, term()}
  defp create_pre_restore_backup do
    Logger.info("Creating pre-restore backup (database + photos)")
    timestamp = format_timestamp(DateTime.utc_now())
    backup_key = "#{@pre_restore_prefix}#{timestamp}.sql.gz"

    with {:ok, dump_path} <- create_database_dump(),
         :ok <- LocalStorage.upload(dump_path, backup_key),
         :ok <- File.rm(dump_path),
         {:ok, _count} <- backup_photos_for_pre_restore(timestamp) do
      Logger.info("Pre-restore backup created: #{backup_key}")
      {:ok, backup_key}
    end
  end

  @spec backup_photos_for_pre_restore(String.t()) :: {:ok, integer()} | {:error, term()}
  defp backup_photos_for_pre_restore(timestamp) do
    uploads_dir = uploads_directory()
    pre_restore_photos_prefix = "#{@pre_restore_prefix}photos-#{timestamp}/"

    if File.dir?(uploads_dir) do
      LocalStorage.sync_directory(uploads_dir, pre_restore_photos_prefix)
    else
      {:ok, 0}
    end
  end

  @spec restore_photos() :: :ok
  defp restore_photos do
    Logger.info("Restoring photos from backup")
    uploads_dir = uploads_directory()
    backup_photos_dir = Path.join(LocalStorage.base_path(), @photos_prefix)

    if File.dir?(backup_photos_dir) do
      File.mkdir_p!(uploads_dir)

      case File.ls(backup_photos_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&File.regular?(Path.join(backup_photos_dir, &1)))
          |> Enum.each(fn filename ->
            src = Path.join(backup_photos_dir, filename)
            dest = Path.join(uploads_dir, filename)
            File.cp(src, dest)
          end)

          Logger.info("Photos restored to #{uploads_dir}")

        {:error, reason} ->
          Logger.warning("Failed to list backup photos: #{inspect(reason)}")
      end
    else
      Logger.info("No backup photos to restore")
    end

    :ok
  end

  @spec cleanup_prefix(String.t(), DateTime.t()) :: :ok
  defp cleanup_prefix(prefix, cutoff) do
    {:ok, objects} = LocalStorage.list_objects(prefix)

    objects
    |> Enum.filter(&DateTime.before?(&1.updated, cutoff))
    |> Enum.each(fn obj ->
      Logger.info("Deleting old backup: #{obj.key}")
      LocalStorage.delete(obj.key)
    end)

    :ok
  end

  @spec format_timestamp(DateTime.t()) :: String.t()
  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H-%M-%SZ")
  end

  @spec uploads_directory() :: String.t()
  defp uploads_directory do
    Application.app_dir(:inventory_locator, "priv/static/uploads")
  end
end
