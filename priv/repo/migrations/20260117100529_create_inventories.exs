defmodule InventoryLocator.Repo.Migrations.CreateInventories do
  use Ecto.Migration

  def change do
    create table(:inventories) do
      add :name, :string, null: false
      add :description, :text

      timestamps()
    end

    create unique_index(:inventories, [:name])
  end
end
