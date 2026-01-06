defmodule InventoryLocator.Inventory.Cell do
  use Ecto.Schema
  import Ecto.Changeset

  alias InventoryLocator.Inventory.Bin

  schema "cells" do
    field :code, :string
    field :name, :string

    belongs_to :bin, Bin

    timestamps()
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:code, :name, :bin_id])
    |> validate_required([:code, :bin_id])
    |> foreign_key_constraint(:bin_id)
    |> unique_constraint([:bin_id, :code], name: :cells_bin_id_code_index)
  end
end
