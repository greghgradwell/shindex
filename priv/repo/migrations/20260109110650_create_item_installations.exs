defmodule InventoryLocator.Repo.Migrations.CreateItemInstallations do
  use Ecto.Migration

  def change do
    create table(:item_installations) do
      add :item_type_id, references(:item_types, on_delete: :delete_all), null: false
      add :project_name, :string, null: false
      add :quantity, :integer, null: false

      timestamps()
    end

    create index(:item_installations, [:item_type_id])
    create index(:item_installations, [:project_name])
    create unique_index(:item_installations, [:item_type_id, :project_name])

    create constraint(:item_installations, :quantity_must_be_positive, check: "quantity > 0")
  end
end
