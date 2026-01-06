defmodule InventoryLocator.Repo.Migrations.CreateBins do
  use Ecto.Migration

  def change do
    create table(:bins) do
      add :code, :string, null: false
      add :name, :string
      add :shelf_id, references(:shelves, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:bins, [:shelf_id])
    create unique_index(:bins, [:shelf_id, :code])
  end
end
