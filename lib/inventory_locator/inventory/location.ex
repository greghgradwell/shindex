defmodule InventoryLocator.Inventory.Location do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Inventory.LocationCode

  typed_schema "locations" do
    field :full_code, :string

    belongs_to :bin, Bin

    has_many :item_types, ItemType

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:full_code, :bin_id])
    |> validate_required([:full_code, :bin_id])
    |> validate_location_code_format()
    |> foreign_key_constraint(:bin_id)
    |> unique_constraint(:bin_id)
  end

  @spec validate_location_code_format(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_location_code_format(changeset) do
    validate_change(changeset, :full_code, fn :full_code, code ->
      if LocationCode.valid?(code) do
        []
      else
        [full_code: "must be in format SHELF-BIN (e.g., A-1)"]
      end
    end)
  end
end
