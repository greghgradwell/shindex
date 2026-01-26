defmodule InventoryLocator.Repo.Migrations.AddSourceUrlToItemTypes do
  use Ecto.Migration

  def change do
    alter table(:item_types) do
      add :source_url, :string
    end
  end
end
