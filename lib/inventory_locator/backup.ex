defmodule InventoryLocator.Backup do
  @moduledoc false
  alias InventoryLocator.Backup.LocalStorage
  alias InventoryLocator.Backup.Scheduler
  alias InventoryLocator.Backup.Settings
  alias InventoryLocator.Backup.Worker
  alias InventoryLocator.Repo

  @settings_id 1

  @spec configured?() :: boolean()
  def configured? do
    LocalStorage.configured?()
  end

  @spec get_settings() :: Settings.t()
  def get_settings do
    Repo.get!(Settings, @settings_id)
  end

  @spec update_settings(map()) :: {:ok, Settings.t()} | {:error, Ecto.Changeset.t()}
  def update_settings(attrs) do
    settings = get_settings()

    case settings |> Settings.changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        Scheduler.configure_from_settings(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  @spec change_settings(Settings.t(), map()) :: Ecto.Changeset.t()
  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @spec list_daily_backups() :: {:ok, [LocalStorage.object_info()]} | {:error, term()}
  def list_daily_backups do
    Worker.list_daily_backups()
  end

  @spec list_weekly_backups() :: {:ok, [LocalStorage.object_info()]} | {:error, term()}
  def list_weekly_backups do
    Worker.list_weekly_backups()
  end

  @spec run_daily_backup() :: {:ok, String.t()} | {:error, term()}
  def run_daily_backup do
    Worker.run_daily()
  end

  @spec run_weekly_backup() :: {:ok, String.t()} | {:error, term()}
  def run_weekly_backup do
    Worker.run_weekly()
  end

  @spec restore_backup(String.t()) :: :ok | {:error, term()}
  def restore_backup(backup_key) do
    Worker.restore(backup_key)
  end

  @spec delete_backup(String.t()) :: :ok | {:error, term()}
  def delete_backup(backup_key) do
    LocalStorage.delete(backup_key)
  end

  @spec format_size(integer()) :: String.t()
  def format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_size(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  def format_size(bytes), do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  @spec extract_timestamp_from_key(String.t()) :: String.t()
  def extract_timestamp_from_key(key) do
    key
    |> Path.basename()
    |> String.replace(~r/\.sql\.gz$/, "")
    |> format_backup_timestamp()
  end

  @spec format_backup_timestamp(String.t()) :: String.t()
  defp format_backup_timestamp(timestamp) do
    case Regex.run(~r/(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})Z/, timestamp) do
      [_, year, month, day, hour, min, _sec] ->
        hour_int = String.to_integer(hour)
        period = if hour_int < 12, do: "AM", else: "PM"
        display_hour = rem(hour_int, 12)
        display_hour = if display_hour == 0, do: 12, else: display_hour
        "#{year}-#{month}-#{day} #{display_hour}:#{min} #{period}"

      _ ->
        timestamp
    end
  end
end
