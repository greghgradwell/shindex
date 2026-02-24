defmodule InventoryLocator.Marketplace.Request do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Accounts.User
  alias InventoryLocator.Marketplace.Listing

  typed_schema "requests" do
    field :message, :string
    field :resolved, :boolean

    belongs_to :listing, Listing
    belongs_to :requester, User

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(request, attrs) do
    request
    |> cast(attrs, [:message, :resolved, :listing_id, :requester_id])
    |> validate_required([:resolved, :listing_id, :requester_id])
    |> unique_constraint([:listing_id, :requester_id])
    |> foreign_key_constraint(:listing_id)
    |> foreign_key_constraint(:requester_id)
  end
end
