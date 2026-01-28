defmodule InventoryLocator.Inventory.Shelf do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Inv

  typed_schema "shelves" do
    field :code, :string
    field :name, :string
    field :description, :string
    field :system, :boolean, default: false

    belongs_to :inventory, Inv
    has_many :bins, Bin

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(shelf, attrs) do
    shelf
    |> cast(attrs, [:code, :name, :description, :inventory_id, :system])
    |> validate_required([:code, :inventory_id])
    |> validate_code()
    |> unique_constraint(:code, name: :shelves_inventory_id_code_index)
    |> foreign_key_constraint(:inventory_id)
  end

  @unsorted_code "UNSORTED"

  @spec unsorted_code() :: String.t()
  def unsorted_code, do: @unsorted_code

  @spec system?(t()) :: boolean()
  def system?(%__MODULE__{system: system}), do: system == true

  @max_code_length 50

  @spec max_code_length() :: integer()
  def max_code_length, do: @max_code_length

  @spec valid_code?(any()) :: boolean()
  def valid_code?(code) when is_binary(code) do
    String.length(code) > 0 &&
      String.length(code) <= @max_code_length &&
      Regex.match?(~r/^[a-zA-Z]([a-zA-Z0-9_]*[a-zA-Z0-9])?$/, code)
  end

  def valid_code?(_), do: false

  @spec validate_code(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_code(changeset) do
    validate_change(changeset, :code, fn :code, code ->
      if valid_code?(code) do
        []
      else
        [code: "must start with a letter and contain only letters, numbers, and underscores"]
      end
    end)
  end
end
