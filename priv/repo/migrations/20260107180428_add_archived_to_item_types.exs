defmodule InventoryLocator.Repo.Migrations.AddArchivedToItemTypes do
  use Ecto.Migration

  def change do
    alter table(:item_types) do
      add :archived, :boolean, default: false, null: false
    end

    create index(:item_types, [:archived])
  end
end
