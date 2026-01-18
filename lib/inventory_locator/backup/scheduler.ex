defmodule InventoryLocator.Backup.Scheduler do
  @moduledoc false
  use Quantum, otp_app: :inventory_locator

  alias Crontab.CronExpression.Parser
  alias InventoryLocator.Backup
  alias InventoryLocator.Backup.Settings
  alias InventoryLocator.Backup.Worker

  require Logger

  @daily_job_name :daily_backup
  @weekly_job_name :weekly_backup

  @spec configure_from_settings(Settings.t()) :: :ok
  def configure_from_settings(%Settings{} = settings) do
    if settings.enabled do
      configure_daily_job(settings.daily_backup_hour)
      configure_weekly_job(settings.weekly_backup_hour, settings.weekly_backup_day)

      Logger.info(
        "Backup scheduler configured: daily at #{settings.daily_backup_hour}:00, weekly on #{Settings.day_name(settings.weekly_backup_day)} at #{settings.weekly_backup_hour}:00"
      )
    else
      delete_job(@daily_job_name)
      delete_job(@weekly_job_name)
      Logger.info("Backup scheduler disabled")
    end

    :ok
  end

  @spec run_scheduled_daily() :: :ok
  def run_scheduled_daily do
    settings = Backup.get_settings()

    if settings.enabled do
      case Worker.run_daily() do
        {:ok, _key} ->
          Worker.cleanup_old_backups(
            settings.daily_retention_days,
            settings.weekly_retention_weeks
          )

        {:error, _reason} ->
          :ok
      end
    end

    :ok
  end

  @spec run_scheduled_weekly() :: :ok
  def run_scheduled_weekly do
    settings = Backup.get_settings()

    if settings.enabled do
      Worker.run_weekly()
    end

    :ok
  end

  @spec configure_daily_job(integer()) :: :ok
  defp configure_daily_job(hour) do
    delete_job(@daily_job_name)

    new_job()
    |> Quantum.Job.set_name(@daily_job_name)
    |> Quantum.Job.set_schedule(Parser.parse!("0 #{hour} * * *"))
    |> Quantum.Job.set_task({__MODULE__, :run_scheduled_daily, []})
    |> add_job()

    :ok
  end

  @spec configure_weekly_job(integer(), integer()) :: :ok
  defp configure_weekly_job(hour, day) do
    delete_job(@weekly_job_name)

    new_job()
    |> Quantum.Job.set_name(@weekly_job_name)
    |> Quantum.Job.set_schedule(Parser.parse!("0 #{hour} * * #{day}"))
    |> Quantum.Job.set_task({__MODULE__, :run_scheduled_weekly, []})
    |> add_job()

    :ok
  end
end
