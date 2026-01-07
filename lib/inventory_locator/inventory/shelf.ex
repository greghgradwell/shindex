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
    |> validate_code()
    |> unique_constraint(:code)
  end

  @max_code_length 50

  def max_code_length, do: @max_code_length

  def valid_code?(code) when is_binary(code) do
    String.length(code) > 0 &&
      String.length(code) <= @max_code_length &&
      Regex.match?(~r/^[a-zA-Z]([a-zA-Z_]*[a-zA-Z])?$/, code)
  end

  def valid_code?(_), do: false

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
