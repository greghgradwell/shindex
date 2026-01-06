defmodule InventoryLocator.Repo.Migrations.CreateShelves do
  use Ecto.Migration

  def change do
    create table(:shelves) do
      add :code, :string, null: false
      add :name, :string
      add :description, :text

      timestamps()
    end

    create unique_index(:shelves, [:code])
  end
end
