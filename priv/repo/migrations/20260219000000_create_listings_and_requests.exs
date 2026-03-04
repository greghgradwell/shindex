defmodule InventoryLocator.Repo.Migrations.CreateListingsAndRequests do
  use Ecto.Migration

  def change do
    create table(:listings) do
      add :item_type_id, references(:item_types, on_delete: :restrict), null: false
      add :type, :string, null: false
      add :price, :decimal
      add :notes, :text
      add :active, :boolean, null: false

      timestamps()
    end

    create unique_index(:listings, [:item_type_id, :type])

    create table(:requests) do
      add :listing_id, references(:listings, on_delete: :delete_all), null: false
      add :requester_id, references(:users, on_delete: :delete_all), null: false
      add :message, :text
      add :resolved, :boolean, null: false

      timestamps()
    end

    create unique_index(:requests, [:listing_id, :requester_id])
  end
end
