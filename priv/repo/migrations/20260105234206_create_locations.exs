defmodule InventoryLocator.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations) do
      add :full_code, :string, null: false
      add :cell_id, references(:cells, on_delete: :restrict), null: false

      timestamps()
    end

    create unique_index(:locations, [:cell_id])
  end
end
