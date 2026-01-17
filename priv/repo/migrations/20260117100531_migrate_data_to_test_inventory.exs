defmodule InventoryLocator.Repo.Migrations.MigrateDataToTestInventory do
  use Ecto.Migration

  def up do
    # Create the Test inventory for existing data
    execute """
    INSERT INTO inventories (name, description, inserted_at, updated_at)
    VALUES ('Test', 'Development and testing inventory', NOW(), NOW())
    """

    # Assign all existing shelves to the Test inventory
    execute """
    UPDATE shelves
    SET inventory_id = (SELECT id FROM inventories WHERE name = 'Test')
    WHERE inventory_id IS NULL
    """

    # Assign all existing item_types to the Test inventory
    execute """
    UPDATE item_types
    SET inventory_id = (SELECT id FROM inventories WHERE name = 'Test')
    WHERE inventory_id IS NULL
    """

    # Make inventory_id NOT NULL on both tables
    alter table(:shelves) do
      modify :inventory_id, :bigint, null: false
    end

    alter table(:item_types) do
      modify :inventory_id, :bigint, null: false
    end

    # Create unique constraint: shelf codes must be unique within an inventory
    create unique_index(:shelves, [:inventory_id, :code])
  end

  def down do
    drop unique_index(:shelves, [:inventory_id, :code])

    alter table(:shelves) do
      modify :inventory_id, :bigint, null: true
    end

    alter table(:item_types) do
      modify :inventory_id, :bigint, null: true
    end

    execute """
    UPDATE shelves SET inventory_id = NULL
    """

    execute """
    UPDATE item_types SET inventory_id = NULL
    """

    execute """
    DELETE FROM inventories WHERE name = 'Test'
    """
  end
end
