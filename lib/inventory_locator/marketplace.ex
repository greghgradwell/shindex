defmodule InventoryLocator.Marketplace do
  @moduledoc false
  import Ecto.Query, warn: false

  alias InventoryLocator.Inventory
  alias InventoryLocator.Marketplace.Listing
  alias InventoryLocator.Marketplace.Request
  alias InventoryLocator.Repo

  require Logger

  # Listings

  @spec create_listing(map()) :: {:ok, Listing.t()} | {:error, Ecto.Changeset.t()}
  def create_listing(attrs) do
    %Listing{}
    |> Listing.changeset(attrs)
    |> Repo.insert()
  end

  @spec deactivate_listing(Listing.t()) :: {:ok, Listing.t()} | {:error, Ecto.Changeset.t()}
  def deactivate_listing(%Listing{} = listing) do
    listing
    |> Listing.changeset(%{active: false})
    |> Repo.update()
  end

  @spec list_listings_for_item(integer()) :: [Listing.t()]
  def list_listings_for_item(item_type_id) do
    Repo.all(
      from(l in Listing,
        where: l.item_type_id == ^item_type_id,
        order_by: l.type,
        preload: [requests: :requester]
      )
    )
  end

  @spec list_active_listings_for_item(integer()) :: [Listing.t()]
  def list_active_listings_for_item(item_type_id) do
    Repo.all(
      from(l in Listing,
        where: l.item_type_id == ^item_type_id and l.active == true,
        order_by: l.type
      )
    )
  end

  @spec listing_types_for_items([integer()]) :: %{integer() => [String.t()]}
  def listing_types_for_items([]), do: %{}

  def listing_types_for_items(item_ids) do
    Repo.all(
      from(l in Listing,
        where: l.item_type_id in ^item_ids and l.active == true,
        select: {l.item_type_id, l.type}
      )
    )
    |> Enum.group_by(fn {id, _type} -> id end, fn {_id, type} -> type end)
  end

  # Requests

  @spec create_request(map()) ::
          {:ok, Request.t()}
          | {:error, :already_requested | :listing_inactive | :unauthorized | Ecto.Changeset.t()}
  def create_request(attrs) do
    listing_id = Map.fetch!(attrs, :listing_id)
    requester_id = Map.fetch!(attrs, :requester_id)
    listing = Repo.get!(Listing, listing_id) |> Repo.preload(:item_type)

    cond do
      not Inventory.user_can_access?(requester_id, listing.item_type.inventory_id) ->
        {:error, :unauthorized}

      not listing.active ->
        {:error, :listing_inactive}

      true ->
        case %Request{}
             |> Request.changeset(Map.put(attrs, :resolved, false))
             |> Repo.insert() do
          {:ok, request} ->
            broadcast_new_request(listing, request)
            {:ok, request}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            if Keyword.has_key?(errors, :listing_id) and
                 match?({_, [constraint: :unique, constraint_name: _]}, Keyword.get(errors, :listing_id)) do
              {:error, :already_requested}
            else
              {:error, changeset}
            end
        end
    end
  end

  @spec resolve_request(Request.t()) :: {:ok, Request.t()} | {:error, Ecto.Changeset.t()}
  def resolve_request(%Request{} = request) do
    request
    |> Request.changeset(%{resolved: true})
    |> Repo.update()
  end

  @spec unresolve_request(Request.t()) :: {:ok, Request.t()} | {:error, Ecto.Changeset.t()}
  def unresolve_request(%Request{} = request) do
    request
    |> Request.changeset(%{resolved: false})
    |> Repo.update()
  end

  @spec get_request!(integer()) :: Request.t()
  def get_request!(id), do: Repo.get!(Request, id)

  @spec get_request_for_inventory(integer(), integer()) :: Request.t() | nil
  def get_request_for_inventory(request_id, inventory_id) do
    Repo.one(
      from(r in Request,
        join: l in assoc(r, :listing),
        join: it in assoc(l, :item_type),
        where: r.id == ^request_id and it.inventory_id == ^inventory_id
      )
    )
  end

  @spec list_requests_for_inventory(integer()) :: [Request.t()]
  def list_requests_for_inventory(inventory_id) do
    Repo.all(
      from(r in Request,
        join: l in assoc(r, :listing),
        join: it in assoc(l, :item_type),
        where: it.inventory_id == ^inventory_id,
        order_by: [desc: r.inserted_at],
        preload: [requester: [], listing: {l, item_type: it}]
      )
    )
  end

  @spec list_requests_by_user(integer(), integer()) :: [Request.t()]
  def list_requests_by_user(user_id, inventory_id) do
    Repo.all(
      from(r in Request,
        join: l in assoc(r, :listing),
        join: it in assoc(l, :item_type),
        where: r.requester_id == ^user_id and it.inventory_id == ^inventory_id,
        order_by: [desc: r.inserted_at],
        preload: [listing: {l, item_type: it}]
      )
    )
  end

  @spec user_requests_for_item(integer(), integer()) :: [Request.t()]
  def user_requests_for_item(user_id, item_type_id) do
    Repo.all(
      from(r in Request,
        join: l in assoc(r, :listing),
        where: r.requester_id == ^user_id and l.item_type_id == ^item_type_id,
        preload: :listing
      )
    )
  end

  @spec count_unresolved_requests(integer()) :: non_neg_integer()
  def count_unresolved_requests(inventory_id) do
    Repo.aggregate(
      from(r in Request,
        join: l in assoc(r, :listing),
        join: it in assoc(l, :item_type),
        where: it.inventory_id == ^inventory_id and r.resolved == false
      ),
      :count
    )
  end

  @spec broadcast_new_request(Listing.t(), Request.t()) :: :ok
  defp broadcast_new_request(listing, _request) do
    inventory_id = listing.item_type.inventory_id
    Phoenix.PubSub.broadcast(InventoryLocator.PubSub, "inventory:#{inventory_id}:requests", :new_request)
  end
end
