defmodule InventoryLocator.Inventory.Shelf do
  use Ecto.Schema
  import Ecto.Changeset

  alias InventoryLocator.Inventory.Bin

  schema "shelves" do
    field :code, :string
    field :name, :string
    field :description, :string

    has_many :bins, Bin

    timestamps()
  end

  def changeset(shelf, attrs) do
    shelf
    |> cast(attrs, [:code, :name, :description])
    |> validate_required([:code])
    |> unique_constraint(:code)
  end
end
