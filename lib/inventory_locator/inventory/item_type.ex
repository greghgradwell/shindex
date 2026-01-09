defmodule InventoryLocator.Inventory.ItemType do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Inventory.Location

  typed_schema "item_types" do
    field :name, :string
    field :description, :string
    field :manufacturer, :string
    field :model, :string
    field :quantity, :integer
    field :photo_path, :string
    field :archived, :boolean

    belongs_to :location, Location

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(item_type, attrs) do
    item_type
    |> cast(attrs, [
      :name,
      :description,
      :manufacturer,
      :model,
      :quantity,
      :photo_path,
      :location_id,
      :archived
    ])
    |> validate_required([:name, :quantity, :archived])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_location_when_active()
    |> foreign_key_constraint(:location_id)
  end

  @spec validate_location_when_active(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_location_when_active(changeset) do
    archived = Ecto.Changeset.get_field(changeset, :archived)

    archived =
      if is_nil(archived) do
        false
      else
        archived
      end

    location_id = Ecto.Changeset.get_field(changeset, :location_id)

    if not archived and is_nil(location_id) do
      Ecto.Changeset.add_error(changeset, :location_id, "is required for active items")
    else
      changeset
    end
  end
end
