defmodule InventoryLocator.Inventory.Document do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Media

  typed_schema "documents" do
    field :filename, :string
    field :storage_path, :string
    field :content_type, :string
    field :size_bytes, :integer

    belongs_to :item_type, ItemType, foreign_key: :item_id

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:filename, :storage_path, :content_type, :size_bytes, :item_id])
    |> validate_required([:filename, :storage_path, :content_type, :size_bytes, :item_id])
    |> validate_number(:size_bytes, greater_than: 0)
    |> validate_content_type()
    |> foreign_key_constraint(:item_id)
  end

  @spec validate_content_type(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_content_type(changeset) do
    validate_change(changeset, :content_type, fn :content_type, content_type ->
      if content_type in Media.allowed_document_content_types() do
        []
      else
        [content_type: "must be PDF, PNG, or JPEG"]
      end
    end)
  end
end
