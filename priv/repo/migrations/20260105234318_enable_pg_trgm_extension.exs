defmodule InventoryLocator.Repo.Migrations.EnablePgTrgmExtension do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "DROP EXTENSION IF EXISTS pg_trgm"

    execute(
      "CREATE INDEX item_types_name_trgm_index ON item_types USING gin (name gin_trgm_ops)",
      "DROP INDEX IF EXISTS item_types_name_trgm_index"
    )
  end
end
