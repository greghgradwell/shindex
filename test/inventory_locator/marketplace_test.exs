defmodule InventoryLocator.MarketplaceTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.InventoryMember
  alias InventoryLocator.Marketplace

  @spec create_item(integer()) :: InventoryLocator.Inventory.ItemType.t()
  defp create_item(inventory_id) do
    Inventory.create_item_with_location!(%{
      inventory_id: inventory_id,
      location_code: "A-1",
      name: "Test Item #{System.unique_integer([:positive])}"
    })
  end

  @spec add_member(integer(), integer()) :: InventoryMember.t()
  defp add_member(inventory_id, user_id) do
    {:ok, member} =
      %InventoryMember{}
      |> InventoryMember.changeset(%{inventory_id: inventory_id, user_id: user_id, role: "viewer"})
      |> InventoryLocator.Repo.insert()

    member
  end

  describe "create_listing/1" do
    test "creates a listing with valid attrs" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)

      assert {:ok, listing} =
               Marketplace.create_listing(%{
                 item_type_id: item.id,
                 type: "borrow",
                 active: true
               })

      assert listing.type == "borrow"
      assert listing.active == true
      assert listing.item_type_id == item.id
    end

    test "creates a listing with price and notes" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)

      assert {:ok, listing} =
               Marketplace.create_listing(%{
                 item_type_id: item.id,
                 type: "sale",
                 price: Decimal.new("49.99"),
                 notes: "Available weekends",
                 active: true
               })

      assert Decimal.equal?(listing.price, Decimal.new("49.99"))
      assert listing.notes == "Available weekends"
    end

    test "validates listing type inclusion" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)

      assert {:error, changeset} =
               Marketplace.create_listing(%{
                 item_type_id: item.id,
                 type: "gift",
                 active: true
               })

      assert errors_on(changeset).type != []
    end

    test "enforces unique constraint on item_type_id + type" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)

      assert {:ok, _listing} =
               Marketplace.create_listing(%{
                 item_type_id: item.id,
                 type: "borrow",
                 active: true
               })

      assert {:error, _changeset} =
               Marketplace.create_listing(%{
                 item_type_id: item.id,
                 type: "borrow",
                 active: true
               })
    end

    test "allows different types for same item" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)

      assert {:ok, _} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      assert {:ok, _} = Marketplace.create_listing(%{item_type_id: item.id, type: "sale", active: true})
      assert {:ok, _} = Marketplace.create_listing(%{item_type_id: item.id, type: "lease", active: true})
    end

    test "validates price >= 0" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)

      assert {:error, changeset} =
               Marketplace.create_listing(%{
                 item_type_id: item.id,
                 type: "sale",
                 price: Decimal.new("-5"),
                 active: true
               })

      assert errors_on(changeset).price != []
    end
  end

  describe "deactivate_listing/1" do
    test "deactivates an active listing" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})

      assert {:ok, deactivated} = Marketplace.deactivate_listing(listing)
      assert deactivated.active == false
    end
  end

  describe "list_listings_for_item/1" do
    test "returns all listings for an item" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      {:ok, _} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, _} = Marketplace.create_listing(%{item_type_id: item.id, type: "sale", active: true})

      listings = Marketplace.list_listings_for_item(item.id)
      assert length(listings) == 2
    end

    test "includes inactive listings" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      Marketplace.deactivate_listing(listing)

      listings = Marketplace.list_listings_for_item(item.id)
      assert length(listings) == 1
    end
  end

  describe "list_active_listings_for_item/1" do
    test "returns only active listings" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, _} = Marketplace.create_listing(%{item_type_id: item.id, type: "sale", active: true})
      Marketplace.deactivate_listing(listing)

      listings = Marketplace.list_active_listings_for_item(item.id)
      assert length(listings) == 1
      assert hd(listings).type == "sale"
    end
  end

  describe "listing_types_for_items/1" do
    test "returns map of item_id to listing types" do
      inventory = create_test_inventory(%{})
      item1 = create_item(inventory.id)
      item2 = create_item(inventory.id)

      {:ok, _} = Marketplace.create_listing(%{item_type_id: item1.id, type: "borrow", active: true})
      {:ok, _} = Marketplace.create_listing(%{item_type_id: item1.id, type: "sale", active: true})
      {:ok, _} = Marketplace.create_listing(%{item_type_id: item2.id, type: "lease", active: true})

      map = Marketplace.listing_types_for_items([item1.id, item2.id])

      assert Enum.sort(map[item1.id]) == ["borrow", "sale"]
      assert map[item2.id] == ["lease"]
    end

    test "excludes inactive listings" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      Marketplace.deactivate_listing(listing)

      map = Marketplace.listing_types_for_items([item.id])
      assert map == %{}
    end

    test "returns empty map for empty list" do
      assert Marketplace.listing_types_for_items([]) == %{}
    end
  end

  describe "create_request/1" do
    test "creates a request for an active listing" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})

      assert {:ok, request} =
               Marketplace.create_request(%{
                 listing_id: listing.id,
                 requester_id: requester.id,
                 message: "I'd like to borrow this"
               })

      assert request.listing_id == listing.id
      assert request.requester_id == requester.id
      assert request.message == "I'd like to borrow this"
      assert request.resolved == false
    end

    test "creates a request without a message" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "sale", active: true})

      assert {:ok, request} =
               Marketplace.create_request(%{
                 listing_id: listing.id,
                 requester_id: requester.id
               })

      assert is_nil(request.message)
    end

    test "returns :listing_inactive for inactive listing" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, listing} = Marketplace.deactivate_listing(listing)

      assert {:error, :listing_inactive} =
               Marketplace.create_request(%{
                 listing_id: listing.id,
                 requester_id: requester.id
               })
    end

    test "prevents duplicate requests (same user, same listing)" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})

      assert {:ok, _request} =
               Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})

      assert {:error, :already_requested} =
               Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})
    end

    test "allows same user to request different listing types" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, borrow} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, sale} = Marketplace.create_listing(%{item_type_id: item.id, type: "sale", active: true})

      assert {:ok, _} = Marketplace.create_request(%{listing_id: borrow.id, requester_id: requester.id})
      assert {:ok, _} = Marketplace.create_request(%{listing_id: sale.id, requester_id: requester.id})
    end

    test "returns :unauthorized when requester has no access to inventory" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      outsider = create_test_user(%{name: "Outsider", role: "member"})
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})

      assert {:error, :unauthorized} =
               Marketplace.create_request(%{listing_id: listing.id, requester_id: outsider.id})
    end

    test "returns :listing_not_found for non-existent listing" do
      requester = create_test_user(%{name: "Requester", role: "member"})

      assert {:error, :listing_not_found} =
               Marketplace.create_request(%{listing_id: -1, requester_id: requester.id})
    end
  end

  describe "resolve_request/1 and unresolve_request/1" do
    test "resolves a request" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, request} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})

      assert {:ok, resolved} = Marketplace.resolve_request(request)
      assert resolved.resolved == true
    end

    test "unresolves a request" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, request} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})
      {:ok, resolved} = Marketplace.resolve_request(request)

      assert {:ok, unresolved} = Marketplace.unresolve_request(resolved)
      assert unresolved.resolved == false
    end
  end

  describe "get_request_for_inventory/2" do
    test "returns request when it belongs to the inventory" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, request} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})

      assert found = Marketplace.get_request_for_inventory(request.id, inventory.id)
      assert found.id == request.id
    end

    test "returns nil when request belongs to a different inventory" do
      inventory1 = create_test_inventory(%{})
      inventory2 = create_test_inventory(%{})
      item = create_item(inventory1.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory1.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, request} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})

      assert is_nil(Marketplace.get_request_for_inventory(request.id, inventory2.id))
    end
  end

  describe "count_unresolved_requests/1" do
    test "counts unresolved requests for an inventory" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester1 = create_test_user(%{name: "Requester 1", role: "member"})
      requester2 = create_test_user(%{name: "Requester 2", role: "member"})
      add_member(inventory.id, requester1.id)
      add_member(inventory.id, requester2.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, _} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester1.id})
      {:ok, r2} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester2.id})

      assert Marketplace.count_unresolved_requests(inventory.id) == 2

      Marketplace.resolve_request(r2)
      assert Marketplace.count_unresolved_requests(inventory.id) == 1
    end

    test "returns 0 for inventory with no requests" do
      inventory = create_test_inventory(%{})
      assert Marketplace.count_unresolved_requests(inventory.id) == 0
    end
  end

  describe "list_requests_for_inventory/1" do
    test "returns all requests for an inventory" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, _} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})

      requests = Marketplace.list_requests_for_inventory(inventory.id)
      assert length(requests) == 1
      assert hd(requests).requester.name == "Requester"
      assert hd(requests).listing.item_type.name =~ "Test Item"
    end
  end

  describe "list_requests_by_user/2" do
    test "returns requests by a user for an inventory" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, _} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})

      requests = Marketplace.list_requests_by_user(requester.id, inventory.id)
      assert length(requests) == 1
    end

    test "does not return requests for other inventories" do
      inventory1 = create_test_inventory(%{})
      inventory2 = create_test_inventory(%{})
      item1 = create_item(inventory1.id)
      item2 = create_item(inventory2.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory1.id, requester.id)
      add_member(inventory2.id, requester.id)
      {:ok, listing1} = Marketplace.create_listing(%{item_type_id: item1.id, type: "borrow", active: true})
      {:ok, listing2} = Marketplace.create_listing(%{item_type_id: item2.id, type: "borrow", active: true})
      {:ok, _} = Marketplace.create_request(%{listing_id: listing1.id, requester_id: requester.id})
      {:ok, _} = Marketplace.create_request(%{listing_id: listing2.id, requester_id: requester.id})

      requests = Marketplace.list_requests_by_user(requester.id, inventory1.id)
      assert length(requests) == 1
    end
  end

  describe "user_requests_for_item/2" do
    test "returns user's requests for a specific item" do
      inventory = create_test_inventory(%{})
      item = create_item(inventory.id)
      requester = create_test_user(%{name: "Requester", role: "member"})
      add_member(inventory.id, requester.id)
      {:ok, listing} = Marketplace.create_listing(%{item_type_id: item.id, type: "borrow", active: true})
      {:ok, _} = Marketplace.create_request(%{listing_id: listing.id, requester_id: requester.id})

      requests = Marketplace.user_requests_for_item(requester.id, item.id)
      assert length(requests) == 1
    end
  end

  describe "listing_types filter in Inventory context" do
    test "search_items filters by listing types" do
      inventory = create_test_inventory(%{})
      item1 = create_item(inventory.id)
      item2 = create_item(inventory.id)
      {:ok, _} = Marketplace.create_listing(%{item_type_id: item1.id, type: "borrow", active: true})

      {items, count} =
        Inventory.search_items(inventory.id, "",
          show_archived: false,
          filters: [],
          page: 1,
          page_size: 48,
          listing_types: ["borrow"]
        )

      assert count == 1
      assert hd(items).id == item1.id
      refute Enum.any?(items, fn i -> i.id == item2.id end)
    end

    test "list_all_items filters by listing types" do
      inventory = create_test_inventory(%{})
      item1 = create_item(inventory.id)
      _item2 = create_item(inventory.id)
      {:ok, _} = Marketplace.create_listing(%{item_type_id: item1.id, type: "sale", active: true})

      {items, count} =
        Inventory.list_all_items(inventory.id,
          show_archived: false,
          sort_by: :name,
          sort_order: :asc,
          page: 1,
          page_size: 48,
          listing_types: ["sale"]
        )

      assert count == 1
      assert hd(items).id == item1.id
    end
  end
end
