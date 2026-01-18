defmodule InventoryLocator.Backup.Settings do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          enabled: boolean(),
          daily_retention_days: integer(),
          weekly_retention_weeks: integer(),
          daily_backup_hour: integer(),
          weekly_backup_hour: integer(),
          weekly_backup_day: integer(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "backup_settings" do
    field :enabled, :boolean
    field :daily_retention_days, :integer
    field :weekly_retention_weeks, :integer
    field :daily_backup_hour, :integer
    field :weekly_backup_hour, :integer
    field :weekly_backup_day, :integer

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :enabled,
      :daily_retention_days,
      :weekly_retention_weeks,
      :daily_backup_hour,
      :weekly_backup_hour,
      :weekly_backup_day
    ])
    |> validate_required([
      :enabled,
      :daily_retention_days,
      :weekly_retention_weeks,
      :daily_backup_hour,
      :weekly_backup_hour,
      :weekly_backup_day
    ])
    |> validate_number(:daily_retention_days, greater_than: 0, less_than_or_equal_to: 30)
    |> validate_number(:weekly_retention_weeks, greater_than: 0, less_than_or_equal_to: 52)
    |> validate_number(:daily_backup_hour, greater_than_or_equal_to: 0, less_than: 24)
    |> validate_number(:weekly_backup_hour, greater_than_or_equal_to: 0, less_than: 24)
    |> validate_number(:weekly_backup_day, greater_than_or_equal_to: 0, less_than: 7)
  end

  @spec day_name(integer()) :: String.t()
  def day_name(0), do: "Sunday"
  def day_name(1), do: "Monday"
  def day_name(2), do: "Tuesday"
  def day_name(3), do: "Wednesday"
  def day_name(4), do: "Thursday"
  def day_name(5), do: "Friday"
  def day_name(6), do: "Saturday"

  @spec hour_label(integer()) :: String.t()
  def hour_label(hour) when hour >= 0 and hour < 24 do
    period = if hour < 12, do: "AM", else: "PM"
    display_hour = rem(hour, 12)
    display_hour = if display_hour == 0, do: 12, else: display_hour
    "#{display_hour}:00 #{period}"
  end
end
