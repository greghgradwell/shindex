defmodule InventoryLocator.Repo.Migrations.CreateBackupSettings do
  use Ecto.Migration

  def change do
    create table(:backup_settings) do
      add :enabled, :boolean, null: false, default: true
      add :daily_retention_days, :integer, null: false, default: 7
      add :weekly_retention_weeks, :integer, null: false, default: 4
      add :daily_backup_hour, :integer, null: false, default: 2
      add :weekly_backup_hour, :integer, null: false, default: 3
      add :weekly_backup_day, :integer, null: false, default: 0

      timestamps()
    end

    # Singleton constraint: only one row allowed (id must be 1)
    create constraint(:backup_settings, :singleton, check: "id = 1")

    # Seed the default settings row
    execute(
      "INSERT INTO backup_settings (id, enabled, daily_retention_days, weekly_retention_weeks, daily_backup_hour, weekly_backup_hour, weekly_backup_day, inserted_at, updated_at) VALUES (1, true, 7, 4, 2, 3, 0, NOW(), NOW())",
      "DELETE FROM backup_settings WHERE id = 1"
    )
  end
end
