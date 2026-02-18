defmodule InventoryLocator.Repo.Migrations.AddAuthTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :email, :string
      add :avatar_url, :string
      add :role, :string, null: false

      timestamps()
    end

    create unique_index(:users, [:email], where: "email IS NOT NULL")

    create table(:user_identities) do
      add :provider, :string, null: false
      add :provider_uid, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:user_identities, [:provider, :provider_uid])
    create index(:user_identities, [:user_id])

    create table(:invite_codes) do
      add :code, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :used_by_id, references(:users, on_delete: :nilify_all)
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:invite_codes, [:code])
  end
end
