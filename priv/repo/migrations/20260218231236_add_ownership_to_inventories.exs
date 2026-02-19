defmodule InventoryLocator.Repo.Migrations.AddOwnershipToInventories do
  use Ecto.Migration

  def up do
    alter table(:inventories) do
      add :user_id, references(:users, on_delete: :restrict)
    end

    flush()

    # Assign existing inventories to the first admin user
    execute """
    UPDATE inventories
    SET user_id = (SELECT id FROM users WHERE role = 'admin' ORDER BY inserted_at ASC LIMIT 1)
    WHERE user_id IS NULL
    AND EXISTS (SELECT 1 FROM users WHERE role = 'admin')
    """

    flush()

    alter table(:inventories) do
      modify :user_id, references(:users, on_delete: :restrict),
        null: false,
        from: references(:users, on_delete: :restrict)
    end

    drop_if_exists unique_index(:inventories, [:name])
    create unique_index(:inventories, [:user_id, :name])
  end

  def down do
    drop_if_exists unique_index(:inventories, [:user_id, :name])
    create unique_index(:inventories, [:name])

    alter table(:inventories) do
      remove :user_id
    end
  end
end
