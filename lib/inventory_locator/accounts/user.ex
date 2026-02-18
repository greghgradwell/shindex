defmodule InventoryLocator.Accounts.User do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Accounts.InviteCode
  alias InventoryLocator.Accounts.UserIdentity

  @roles ~w(admin member)

  typed_schema "users" do
    field :name, :string
    field :email, :string
    field :avatar_url, :string
    field :role, :string

    has_many :identities, UserIdentity
    has_many :used_invite_codes, InviteCode, foreign_key: :used_by_id

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :avatar_url, :role])
    |> validate_required([:name, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:email)
  end

  @spec admin?(t()) :: boolean()
  def admin?(%__MODULE__{role: "admin"}), do: true
  def admin?(%__MODULE__{}), do: false

  @spec roles() :: [String.t()]
  def roles, do: @roles
end
