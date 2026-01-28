defmodule InventoryLocator.Repo.Migrations.AddSystemToShelves do
  use Ecto.Migration

  def change do
    alter table(:shelves) do
      add :system, :boolean, default: false, null: false
    end
  end
end
