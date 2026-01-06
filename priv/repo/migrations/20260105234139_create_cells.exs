defmodule InventoryLocator.Repo.Migrations.CreateCells do
  use Ecto.Migration

  def change do
    create table(:cells) do
      add :code, :string, null: false
      add :name, :string
      add :bin_id, references(:bins, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:cells, [:bin_id])
    create unique_index(:cells, [:bin_id, :code])
  end
end
