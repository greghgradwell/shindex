defmodule InventoryLocator.Repo.Migrations.AddInventorySharing do
  use Ecto.Migration

  def change do
    create table(:inventory_members) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :inventory_id, references(:inventories, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps()
    end

    create unique_index(:inventory_members, [:user_id, :inventory_id])

    create table(:inventory_share_codes) do
      add :code, :string, null: false
      add :inventory_id, references(:inventories, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :used_by_id, references(:users, on_delete: :nilify_all)
      add :created_by_id, references(:users, on_delete: :nilify_all), null: false

      timestamps()
    end

    create unique_index(:inventory_share_codes, [:code])
  end
end
