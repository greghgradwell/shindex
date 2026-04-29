defmodule InventoryLocator.Repo.Migrations.RenameInventoryMembersToFriends do
  use Ecto.Migration

  def up do
    rename table(:inventory_members), to: table(:inventory_friends)

    execute "ALTER INDEX inventory_members_pkey RENAME TO inventory_friends_pkey"

    execute "ALTER INDEX inventory_members_user_id_inventory_id_index RENAME TO inventory_friends_user_id_inventory_id_index"

    execute "ALTER TABLE inventory_friends RENAME CONSTRAINT inventory_members_inventory_id_fkey TO inventory_friends_inventory_id_fkey"

    execute "ALTER TABLE inventory_friends RENAME CONSTRAINT inventory_members_user_id_fkey TO inventory_friends_user_id_fkey"
  end

  def down do
    execute "ALTER TABLE inventory_friends RENAME CONSTRAINT inventory_friends_user_id_fkey TO inventory_members_user_id_fkey"

    execute "ALTER TABLE inventory_friends RENAME CONSTRAINT inventory_friends_inventory_id_fkey TO inventory_members_inventory_id_fkey"

    execute "ALTER INDEX inventory_friends_user_id_inventory_id_index RENAME TO inventory_members_user_id_inventory_id_index"

    execute "ALTER INDEX inventory_friends_pkey RENAME TO inventory_members_pkey"

    rename table(:inventory_friends), to: table(:inventory_members)
  end
end
