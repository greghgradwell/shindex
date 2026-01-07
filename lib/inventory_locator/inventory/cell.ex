defmodule InventoryLocator.Inventory.Cell do
  use Ecto.Schema
  import Ecto.Changeset
  alias InventoryLocator.Inventory.IntegerCodeValidator

  alias InventoryLocator.Inventory.Bin

  schema "cells" do
    field :code, :string
    field :name, :string

    belongs_to :bin, Bin

    timestamps()
  end

  @min_code 0
  @max_code 999

  def min_code, do: @min_code
  def max_code, do: @max_code

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:code, :name, :bin_id])
    |> validate_required([:code, :bin_id])
    |> validate_code()
    |> foreign_key_constraint(:bin_id)
    |> unique_constraint([:bin_id, :code], name: :cells_bin_id_code_index)
  end

  def valid_code?(code) do
    IntegerCodeValidator.valid_code?(code, @min_code, @max_code)
  end

  defp validate_code(changeset) do
    validate_change(changeset, :code, fn :code, code ->
      if valid_code?(code) do
        []
      else
        [code: IntegerCodeValidator.error_message(@min_code, @max_code)]
      end
    end)
  end
end
