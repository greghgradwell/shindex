defmodule InventoryLocator.Inventory.Shelf do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Inventory.Bin

  typed_schema "shelves" do
    field :code, :string
    field :name, :string
    field :description, :string

    has_many :bins, Bin

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(shelf, attrs) do
    shelf
    |> cast(attrs, [:code, :name, :description])
    |> validate_required([:code])
    |> validate_code()
    |> unique_constraint(:code)
  end

  @max_code_length 50

  @spec max_code_length() :: integer()
  def max_code_length, do: @max_code_length

  @spec valid_code?(any()) :: boolean()
  def valid_code?(code) when is_binary(code) do
    String.length(code) > 0 &&
      String.length(code) <= @max_code_length &&
      Regex.match?(~r/^[a-zA-Z]([a-zA-Z_]*[a-zA-Z])?$/, code)
  end

  def valid_code?(_), do: false

  @spec validate_code(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_code(changeset) do
    validate_change(changeset, :code, fn :code, code ->
      if valid_code?(code) do
        []
      else
        [code: "must contain only letters and underscores, 1-50 characters"]
      end
    end)
  end
end
