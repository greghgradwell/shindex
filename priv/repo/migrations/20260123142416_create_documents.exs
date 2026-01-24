defmodule InventoryLocator.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :item_id, references(:item_types, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      add :storage_path, :string, null: false
      add :content_type, :string, null: false
      add :size_bytes, :integer, null: false

      timestamps()
    end

    create index(:documents, [:item_id])
  end
end
