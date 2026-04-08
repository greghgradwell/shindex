defmodule InventoryLocator.Repo.Migrations.AddReusableToShareCodes do
  use Ecto.Migration

  def change do
    alter table(:inventory_share_codes) do
      add :reusable, :boolean, null: false, default: false
    end

    # Remove the default after backfilling existing rows
    execute "ALTER TABLE inventory_share_codes ALTER COLUMN reusable DROP DEFAULT",
            "ALTER TABLE inventory_share_codes ALTER COLUMN reusable SET DEFAULT false"

    create unique_index(:inventory_share_codes, [:inventory_id],
             where: "reusable = true",
             name: :inventory_share_codes_unique_reusable_per_inventory
           )
  end
end
