defmodule InventoryLocator.Inventory.Location do
  use Ecto.Schema
  import Ecto.Changeset

  alias InventoryLocator.Inventory.{Cell, ItemType}

  schema "locations" do
    field :full_code, :string

    belongs_to :cell, Cell

    has_one :item_type, ItemType

    timestamps()
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:full_code, :cell_id])
    |> validate_required([:full_code, :cell_id])
    |> foreign_key_constraint(:cell_id)
    |> unique_constraint(:cell_id)
  end
end
