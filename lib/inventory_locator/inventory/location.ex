defmodule InventoryLocator.Inventory.Location do
  use TypedEctoSchema
  import Ecto.Changeset

  alias InventoryLocator.Inventory.{Cell, ItemType}

  typed_schema "locations" do
    field :full_code, :string

    belongs_to :cell, Cell

    has_one :item_type, ItemType

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:full_code, :cell_id])
    |> validate_required([:full_code, :cell_id])
    |> foreign_key_constraint(:cell_id)
    |> unique_constraint(:cell_id)
  end
end
