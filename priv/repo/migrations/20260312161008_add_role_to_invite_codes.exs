defmodule InventoryLocator.Repo.Migrations.AddRoleToInviteCodes do
  use Ecto.Migration

  def change do
    alter table(:invite_codes) do
      add :role, :string, null: false, default: "member"
    end
  end
end
