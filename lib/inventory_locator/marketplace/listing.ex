defmodule InventoryLocator.Marketplace.Listing do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Marketplace.Request

  @types ~w(borrow lease sale)

  typed_schema "listings" do
    field :type, :string
    field :price, :decimal
    field :notes, :string
    field :active, :boolean

    belongs_to :item_type, ItemType
    has_many :requests, Request

    timestamps()
  end

  @spec types() :: [String.t()]
  def types, do: @types

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(listing, attrs) do
    listing
    |> cast(attrs, [:type, :price, :notes, :active, :item_type_id])
    |> validate_required([:type, :active, :item_type_id])
    |> validate_inclusion(:type, @types)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> unique_constraint([:item_type_id, :type])
    |> foreign_key_constraint(:item_type_id)
  end
end
