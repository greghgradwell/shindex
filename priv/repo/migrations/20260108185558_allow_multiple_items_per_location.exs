defmodule InventoryLocator.Repo.Migrations.AllowMultipleItemsPerLocation do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:item_types, [:location_id])
  end
end
