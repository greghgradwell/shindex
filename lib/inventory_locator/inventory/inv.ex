defmodule InventoryLocator.Inventory.Inv do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Inventory.Shelf

  typed_schema "inventories" do
    field :name, :string
    field :description, :string

    has_many :shelves, Shelf, foreign_key: :inventory_id
    has_many :item_types, ItemType, foreign_key: :inventory_id

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(inv, attrs) do
    inv
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 50)
    |> unique_constraint(:name)
  end
end
