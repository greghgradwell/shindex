defmodule InventoryLocator.Backup.LocalStorage do
  @moduledoc false

  @type object_info :: %{
          key: String.t(),
          size: integer(),
          updated: DateTime.t()
        }

  @spec configured?() :: boolean()
  def configured?, do: true

  @spec base_path() :: String.t()
  def base_path do
    Application.get_env(:inventory_locator, __MODULE__)[:path] || default_path()
  end

  @spec upload(String.t(), String.t()) :: :ok | {:error, term()}
  def upload(source_path, key) do
    with {:ok, dest_path} <- safe_path(key),
         :ok <- ensure_directory(dest_path),
         {:ok, _bytes} <- File.copy(source_path, dest_path) do
      :ok
    end
  end

  @spec download(String.t(), String.t()) :: :ok | {:error, term()}
  def download(key, dest_path) do
    with {:ok, source_path} <- safe_path(key),
         {:ok, _bytes} <- File.copy(source_path, dest_path) do
      :ok
    end
  end

  @spec list_objects(String.t()) :: {:ok, [object_info()]}
  def list_objects(prefix) do
    case safe_path(prefix) do
      {:ok, dir_path} ->
        if File.dir?(dir_path) do
          objects =
            case File.ls(dir_path) do
              {:ok, files} ->
                files
                |> Enum.filter(&File.regular?(Path.join(dir_path, &1)))
                |> Enum.map(fn filename ->
                  file_path = Path.join(dir_path, filename)

                  case File.stat(file_path, time: :posix) do
                    {:ok, stat} ->
                      %{
                        key: "#{prefix}#{filename}",
                        size: stat.size,
                        updated: DateTime.from_unix!(stat.mtime)
                      }

                    {:error, _} ->
                      nil
                  end
                end)
                |> Enum.reject(&is_nil/1)
                |> Enum.sort_by(& &1.updated, {:desc, DateTime})

              {:error, _} ->
                []
            end

          {:ok, objects}
        else
          {:ok, []}
        end

      {:error, :invalid_path} ->
        {:ok, []}
    end
  end

  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(key) do
    with {:ok, path} <- safe_path(key) do
      File.rm(path)
    end
  end

  @spec sync_directory(String.t(), String.t()) :: {:ok, integer()} | {:error, term()}
  def sync_directory(source_dir, dest_prefix) do
    with {:ok, _} <- safe_path(dest_prefix),
         {:ok, existing_objects} <- list_objects(dest_prefix) do
      existing_filenames =
        MapSet.new(existing_objects, fn obj ->
          Path.basename(obj.key)
        end)

      source_files =
        case File.ls(source_dir) do
          {:ok, files} -> Enum.filter(files, &File.regular?(Path.join(source_dir, &1)))
          {:error, _} -> []
        end

      copied_count =
        Enum.reduce(source_files, 0, fn filename, count ->
          if MapSet.member?(existing_filenames, filename) do
            count
          else
            source_path = Path.join(source_dir, filename)
            dest_key = "#{dest_prefix}#{filename}"

            case upload(source_path, dest_key) do
              :ok -> count + 1
              {:error, _} -> count
            end
          end
        end)

      {:ok, copied_count}
    end
  end

  # Path validation to prevent directory traversal attacks

  @spec safe_path(String.t()) :: {:ok, String.t()} | {:error, :invalid_path}
  defp safe_path(key) do
    if valid_key?(key) do
      path = Path.join(base_path(), key)
      # Double-check the resolved path is still within base_path
      # (handles edge cases like symlinks)
      if String.starts_with?(Path.expand(path), Path.expand(base_path())) do
        {:ok, path}
      else
        {:error, :invalid_path}
      end
    else
      {:error, :invalid_path}
    end
  end

  @spec valid_key?(String.t()) :: boolean()
  defp valid_key?(key) do
    not String.contains?(key, "..") and
      not String.starts_with?(key, "/") and
      not String.contains?(key, "\0")
  end

  @spec ensure_directory(String.t()) :: :ok | {:error, term()}
  defp ensure_directory(file_path) do
    file_path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  @spec default_path() :: String.t()
  defp default_path do
    Application.app_dir(:inventory_locator, "priv/backups")
  end
end
