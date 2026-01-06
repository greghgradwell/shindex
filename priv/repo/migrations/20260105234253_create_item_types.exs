defmodule InventoryLocator.Repo.Migrations.CreateItemTypes do
  use Ecto.Migration

  def change do
    create table(:item_types) do
      add :name, :string, null: false
      add :description, :text
      add :manufacturer, :string
      add :model, :string
      add :quantity, :integer, null: false, default: 1
      add :photo_path, :string
      add :location_id, references(:locations, on_delete: :restrict), null: false

      timestamps()
    end

    create unique_index(:item_types, [:location_id])
  end
end
