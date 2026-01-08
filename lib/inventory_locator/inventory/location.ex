defmodule InventoryLocator.Inventory.Location do
  use TypedEctoSchema
  import Ecto.Changeset

  alias InventoryLocator.Inventory.{Cell, ItemType, LocationCode}

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
    |> validate_location_code_format()
    |> foreign_key_constraint(:cell_id)
    |> unique_constraint(:cell_id)
  end

  @spec validate_location_code_format(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_location_code_format(changeset) do
    validate_change(changeset, :full_code, fn :full_code, code ->
      if LocationCode.valid?(code) do
        []
      else
        [full_code: "must be in format SHELF-BIN-CELL (e.g., A-1-0)"]
      end
    end)
  end
end
