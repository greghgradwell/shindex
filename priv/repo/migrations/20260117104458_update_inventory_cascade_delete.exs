defmodule InventoryLocator.Repo.Migrations.UpdateInventoryCascadeDelete do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE shelves DROP CONSTRAINT IF EXISTS shelves_inventory_id_fkey"
    execute "ALTER TABLE item_types DROP CONSTRAINT IF EXISTS item_types_inventory_id_fkey"

    execute """
    ALTER TABLE shelves
    ADD CONSTRAINT shelves_inventory_id_fkey
    FOREIGN KEY (inventory_id) REFERENCES inventories(id) ON DELETE CASCADE
    """

    execute """
    ALTER TABLE item_types
    ADD CONSTRAINT item_types_inventory_id_fkey
    FOREIGN KEY (inventory_id) REFERENCES inventories(id) ON DELETE CASCADE
    """
  end

  def down do
    execute "ALTER TABLE shelves DROP CONSTRAINT IF EXISTS shelves_inventory_id_fkey"
    execute "ALTER TABLE item_types DROP CONSTRAINT IF EXISTS item_types_inventory_id_fkey"

    execute """
    ALTER TABLE shelves
    ADD CONSTRAINT shelves_inventory_id_fkey
    FOREIGN KEY (inventory_id) REFERENCES inventories(id) ON DELETE RESTRICT
    """

    execute """
    ALTER TABLE item_types
    ADD CONSTRAINT item_types_inventory_id_fkey
    FOREIGN KEY (inventory_id) REFERENCES inventories(id) ON DELETE RESTRICT
    """
  end
end
