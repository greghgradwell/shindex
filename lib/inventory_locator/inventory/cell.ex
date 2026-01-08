defmodule InventoryLocator.Inventory.Cell do
  use TypedEctoSchema
  import Ecto.Changeset
  alias InventoryLocator.Inventory.IntegerCodeValidator

  alias InventoryLocator.Inventory.{Bin, Location}

  typed_schema "cells" do
    field :code, :string
    field :name, :string

    belongs_to :bin, Bin
    has_one :location, Location

    timestamps()
  end

  @min_code 1
  @max_code 999

  @spec min_code() :: integer()
  def min_code, do: @min_code

  @spec max_code() :: integer()
  def max_code, do: @max_code

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:code, :name, :bin_id])
    |> validate_required([:code, :bin_id])
    |> validate_code()
    |> foreign_key_constraint(:bin_id)
    |> unique_constraint([:bin_id, :code], name: :cells_bin_id_code_index)
  end

  @spec valid_code?(any()) :: boolean()
  def valid_code?(code) do
    IntegerCodeValidator.valid_code?(code, @min_code, @max_code)
  end

  @spec validate_code(Ecto.Changeset.t()) :: Ecto.Changeset.t()
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
