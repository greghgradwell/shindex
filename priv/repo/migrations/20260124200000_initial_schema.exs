defmodule InventoryLocator.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def change do
    # Enable pg_trgm extension for fuzzy text search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "DROP EXTENSION IF EXISTS pg_trgm"

    # Inventories - top-level container for organizing items
    create table(:inventories) do
      add :name, :string, null: false
      add :description, :text

      timestamps()
    end

    create unique_index(:inventories, [:name])

    # Shelves - first level of location hierarchy
    create table(:shelves) do
      add :code, :string, null: false
      add :name, :string
      add :description, :text
      add :inventory_id, references(:inventories, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:shelves, [:inventory_id])
    create unique_index(:shelves, [:inventory_id, :code])

    # Bins - second level of location hierarchy (belongs to shelf)
    create table(:bins) do
      add :code, :string, null: false
      add :name, :string
      add :shelf_id, references(:shelves, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:bins, [:shelf_id])
    create unique_index(:bins, [:shelf_id, :code])

    # Locations - physical storage location (one per bin)
    create table(:locations) do
      add :full_code, :string, null: false
      add :bin_id, references(:bins, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:locations, [:bin_id])

    # Item types - the items being tracked
    create table(:item_types) do
      add :name, :string, null: false
      add :description, :text
      add :manufacturer, :string
      add :model, :string
      add :quantity, :integer, null: false, default: 0
      add :photo_path, :string
      add :archived, :boolean, null: false, default: false
      add :location_id, references(:locations, on_delete: :restrict), null: true
      add :inventory_id, references(:inventories, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:item_types, [:location_id])
    create index(:item_types, [:inventory_id])
    create index(:item_types, [:archived])

    # Trigram index for fuzzy search on item names
    execute(
      "CREATE INDEX item_types_name_trgm_idx ON item_types USING gin (name gin_trgm_ops)",
      "DROP INDEX item_types_name_trgm_idx"
    )

    # Constraint: active items must have location, archived items must not
    create constraint(:item_types, :archived_location_constraint,
             check:
               "(archived = false AND location_id IS NOT NULL) OR (archived = true AND location_id IS NULL)"
           )

    # Item installations - track items installed in projects
    create table(:item_installations) do
      add :item_type_id, references(:item_types, on_delete: :delete_all), null: false
      add :project_name, :string, null: false
      add :quantity, :integer, null: false

      timestamps()
    end

    create index(:item_installations, [:item_type_id])
    create index(:item_installations, [:project_name])
    create unique_index(:item_installations, [:item_type_id, :project_name])
    create constraint(:item_installations, :quantity_must_be_positive, check: "quantity > 0")

    # Documents - file attachments for items
    create table(:documents) do
      add :item_id, references(:item_types, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      add :storage_path, :string, null: false
      add :content_type, :string, null: false
      add :size_bytes, :integer, null: false

      timestamps()
    end

    create index(:documents, [:item_id])

    # Backup settings - singleton table for backup configuration
    create table(:backup_settings) do
      add :enabled, :boolean, null: false, default: true
      add :daily_retention_days, :integer, null: false, default: 7
      add :weekly_retention_weeks, :integer, null: false, default: 4
      add :daily_backup_hour, :integer, null: false, default: 2
      add :weekly_backup_hour, :integer, null: false, default: 3
      add :weekly_backup_day, :integer, null: false, default: 0

      timestamps()
    end

    create constraint(:backup_settings, :singleton, check: "id = 1")

    # Seed the default backup settings
    execute(
      "INSERT INTO backup_settings (id, enabled, daily_retention_days, weekly_retention_weeks, daily_backup_hour, weekly_backup_hour, weekly_backup_day, inserted_at, updated_at) VALUES (1, true, 7, 4, 2, 3, 0, NOW(), NOW())",
      "DELETE FROM backup_settings WHERE id = 1"
    )
  end
end
