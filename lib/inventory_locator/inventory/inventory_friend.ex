defmodule InventoryLocator.Inventory.InventoryFriend do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Accounts.User
  alias InventoryLocator.Inventory.Inv

  @roles ~w(viewer)

  typed_schema "inventory_friends" do
    belongs_to :user, User
    belongs_to :inventory, Inv
    field :role, :string

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(friend, attrs) do
    friend
    |> cast(attrs, [:user_id, :inventory_id, :role])
    |> validate_required([:user_id, :inventory_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :inventory_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:inventory_id)
  end
end
