defmodule InventoryLocator.Repo.Migrations.UpdateLocationConstraintForMultiItem do
  use Ecto.Migration

  def up do
    drop constraint(:item_types, :location_required_when_active)

    create constraint(:item_types, :location_required_when_active,
             check: "archived = true OR location_id IS NOT NULL"
           )
  end

  def down do
    drop constraint(:item_types, :location_required_when_active)

    create constraint(:item_types, :location_required_when_active,
             check:
               "(archived = true AND location_id IS NULL) OR (archived = false AND location_id IS NOT NULL)"
           )
  end
end
