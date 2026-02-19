defmodule InventoryLocator.Inventory.Inv do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Accounts.User
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Inventory.Shelf

  typed_schema "inventories" do
    field :name, :string
    field :description, :string

    belongs_to :user, User
    has_many :shelves, Shelf, foreign_key: :inventory_id
    has_many :item_types, ItemType, foreign_key: :inventory_id

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(inv, attrs) do
    inv
    |> cast(attrs, [:name, :description, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 50)
    |> unique_constraint(:name, name: :inventories_user_id_name_index)
  end
end
