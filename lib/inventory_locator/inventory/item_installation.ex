defmodule InventoryLocator.Inventory.ItemInstallation do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Inventory.ItemType

  typed_schema "item_installations" do
    belongs_to :item_type, ItemType
    field :project_name, :string
    field :quantity, :integer

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(installation, attrs) do
    installation
    |> cast(attrs, [:item_type_id, :project_name, :quantity])
    |> validate_required([:item_type_id, :project_name, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> update_change(:project_name, &String.upcase/1)
    |> foreign_key_constraint(:item_type_id)
    |> unique_constraint([:item_type_id, :project_name])
  end
end
