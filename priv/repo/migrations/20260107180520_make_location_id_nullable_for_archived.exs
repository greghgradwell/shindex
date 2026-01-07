defmodule InventoryLocator.Repo.Migrations.MakeLocationIdNullableForArchived do
  use Ecto.Migration

  def up do
    alter table(:item_types) do
      modify :location_id, :bigint, null: true
    end

    create constraint(:item_types, :location_required_when_active,
             check:
               "(archived = true AND location_id IS NULL) OR (archived = false AND location_id IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:item_types, :location_required_when_active)

    alter table(:item_types) do
      modify :location_id, :bigint, null: false
    end
  end
end
