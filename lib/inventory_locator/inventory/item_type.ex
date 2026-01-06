defmodule InventoryLocator.Inventory.ItemType do
  use Ecto.Schema
  import Ecto.Changeset

  alias InventoryLocator.Inventory.Location

  schema "item_types" do
    field :name, :string
    field :description, :string
    field :manufacturer, :string
    field :model, :string
    field :quantity, :integer, default: 1
    field :photo_path, :string

    belongs_to :location, Location

    timestamps()
  end

  def changeset(item_type, attrs) do
    item_type
    |> cast(attrs, [
      :name,
      :description,
      :manufacturer,
      :model,
      :quantity,
      :photo_path,
      :location_id
    ])
    |> validate_required([:name, :location_id])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:location_id)
    |> unique_constraint(:location_id)
  end
end
