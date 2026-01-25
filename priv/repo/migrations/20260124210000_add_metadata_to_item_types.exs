defmodule InventoryLocator.Repo.Migrations.AddMetadataToItemTypes do
  use Ecto.Migration

  def change do
    alter table(:item_types) do
      add :metadata, :map, default: %{}
    end
  end
end
