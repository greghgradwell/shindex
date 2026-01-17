defmodule InventoryLocator.Repo.Migrations.AddInventoryIdToShelvesAndItemTypes do
  use Ecto.Migration

  def change do
    alter table(:shelves) do
      add :inventory_id, references(:inventories, on_delete: :restrict)
    end

    alter table(:item_types) do
      add :inventory_id, references(:inventories, on_delete: :restrict)
    end

    drop unique_index(:shelves, [:code])

    create index(:shelves, [:inventory_id])
    create index(:item_types, [:inventory_id])
  end
end
