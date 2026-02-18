defmodule InventoryLocator.Accounts.UserIdentity do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Accounts.User

  typed_schema "user_identities" do
    field :provider, :string
    field :provider_uid, :string

    belongs_to :user, User

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_uid, :user_id])
    |> validate_required([:provider, :provider_uid, :user_id])
    |> unique_constraint([:provider, :provider_uid])
    |> foreign_key_constraint(:user_id)
  end
end
