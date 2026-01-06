defmodule InventoryLocator.Inventory.Bin do
  use Ecto.Schema
  import Ecto.Changeset

  alias InventoryLocator.Inventory.{Shelf, Cell}

  schema "bins" do
    field :code, :string
    field :name, :string

    belongs_to :shelf, Shelf
    has_many :cells, Cell

    timestamps()
  end

  def changeset(bin, attrs) do
    bin
    |> cast(attrs, [:code, :name, :shelf_id])
    |> validate_required([:code, :shelf_id])
    |> foreign_key_constraint(:shelf_id)
    |> unique_constraint([:shelf_id, :code], name: :bins_shelf_id_code_index)
  end
end
