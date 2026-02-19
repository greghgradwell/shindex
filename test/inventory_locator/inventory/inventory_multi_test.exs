defmodule InventoryLocator.Inventory.InventoryMultiTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory

  describe "inventory isolation" do
    setup do
      user = create_test_user(%{name: "Test Owner", role: "admin"})
      {:ok, workshop} = Inventory.create_inventory(%{name: "Workshop", user_id: user.id})
      {:ok, kitchen} = Inventory.create_inventory(%{name: "Kitchen", user_id: user.id})
      %{workshop: workshop, kitchen: kitchen, user: user}
    end

    test "items are isolated between inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, _workshop_item} =
        Inventory.create_item_with_location(%{
          inventory_id: workshop.id,
          location_code: "A-1",
          name: "Workshop Screws",
          quantity: 10
        })

      {:ok, _kitchen_item} =
        Inventory.create_item_with_location(%{
          inventory_id: kitchen.id,
          location_code: "A-1",
          name: "Kitchen Utensils",
          quantity: 5
        })

      {workshop_items, _} =
        Inventory.list_all_items(workshop.id,
          show_archived: false,
          sort_by: :name,
          sort_order: :asc,
          page: 1,
          page_size: 100
        )

      {kitchen_items, _} =
        Inventory.list_all_items(kitchen.id,
          show_archived: false,
          sort_by: :name,
          sort_order: :asc,
          page: 1,
          page_size: 100
        )

      assert length(workshop_items) == 1
      assert hd(workshop_items).name == "Workshop Screws"

      assert length(kitchen_items) == 1
      assert hd(kitchen_items).name == "Kitchen Utensils"
    end

    test "search only returns items from specified inventory", %{workshop: workshop, kitchen: kitchen} do
      {:ok, _item1} =
        Inventory.create_item_with_location(%{
          inventory_id: workshop.id,
          location_code: "A-1",
          name: "Hammer",
          description: "Workshop tool"
        })

      {:ok, _item2} =
        Inventory.create_item_with_location(%{
          inventory_id: kitchen.id,
          location_code: "A-1",
          name: "Meat Hammer",
          description: "Kitchen tool"
        })

      {workshop_results, _} =
        Inventory.search_items(workshop.id, "hammer", show_archived: false, filters: [], page: 1, page_size: 100)

      {kitchen_results, _} =
        Inventory.search_items(kitchen.id, "hammer", show_archived: false, filters: [], page: 1, page_size: 100)

      assert length(workshop_results) == 1
      assert hd(workshop_results).name == "Hammer"

      assert length(kitchen_results) == 1
      assert hd(kitchen_results).name == "Meat Hammer"
    end

    test "shelf codes can be reused across inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, workshop_shelf} = Inventory.create_shelf_with_bins(workshop.id, %{code: "A"}, 1)
      {:ok, kitchen_shelf} = Inventory.create_shelf_with_bins(kitchen.id, %{code: "A"}, 1)

      assert workshop_shelf.code == "A"
      assert kitchen_shelf.code == "A"
      assert workshop_shelf.id != kitchen_shelf.id
    end

    test "shelves are isolated between inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, _shelf1} = Inventory.create_shelf_with_bins(workshop.id, %{code: "WORKSHOP"}, 2)
      {:ok, _shelf2} = Inventory.create_shelf_with_bins(kitchen.id, %{code: "KITCHEN"}, 3)

      workshop_shelves = Inventory.list_shelves_with_hierarchy(workshop.id)
      kitchen_shelves = Inventory.list_shelves_with_hierarchy(kitchen.id)

      assert length(workshop_shelves) == 1
      assert hd(workshop_shelves).code == "WORKSHOP"

      assert length(kitchen_shelves) == 1
      assert hd(kitchen_shelves).code == "KITCHEN"
    end

    test "location codes are isolated between inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, _item1} =
        Inventory.create_item_with_location(%{
          inventory_id: workshop.id,
          location_code: "A-1",
          name: "Item 1"
        })

      {:ok, _item2} =
        Inventory.create_item_with_location(%{
          inventory_id: kitchen.id,
          location_code: "B-2",
          name: "Item 2"
        })

      workshop_codes = Inventory.list_location_codes(workshop.id)
      kitchen_codes = Inventory.list_location_codes(kitchen.id)

      assert "A-1" in workshop_codes
      refute "B-2" in workshop_codes

      assert "B-2" in kitchen_codes
      refute "A-1" in kitchen_codes
    end

    test "occupancy stats are isolated between inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, _item1} =
        Inventory.create_item_with_location(%{
          inventory_id: workshop.id,
          location_code: "A-1",
          name: "Item 1"
        })

      {:ok, _item2} =
        Inventory.create_item_with_location(%{
          inventory_id: workshop.id,
          location_code: "A-2",
          name: "Item 2"
        })

      {:ok, _item3} =
        Inventory.create_item_with_location(%{
          inventory_id: kitchen.id,
          location_code: "B-1",
          name: "Item 3"
        })

      workshop_stats = Inventory.count_locations_by_occupancy(workshop.id)
      kitchen_stats = Inventory.count_locations_by_occupancy(kitchen.id)

      assert workshop_stats.occupied == 2
      assert kitchen_stats.occupied == 1
    end

    test "projects are isolated between inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, workshop_item} =
        Inventory.create_item_with_location(%{
          inventory_id: workshop.id,
          location_code: "A-1",
          name: "Workshop Part",
          quantity: 10
        })

      {:ok, kitchen_item} =
        Inventory.create_item_with_location(%{
          inventory_id: kitchen.id,
          location_code: "A-1",
          name: "Kitchen Part",
          quantity: 5
        })

      {:ok, _, _} = Inventory.install_item(workshop_item, "ROBOT", 2)
      {:ok, _, _} = Inventory.install_item(kitchen_item, "RENOVATION", 1)

      workshop_projects = Inventory.list_project_names(workshop.id)
      kitchen_projects = Inventory.list_project_names(kitchen.id)

      assert "ROBOT" in workshop_projects
      refute "RENOVATION" in workshop_projects

      assert "RENOVATION" in kitchen_projects
      refute "ROBOT" in kitchen_projects
    end
  end

  describe "validate_location_code with inventory" do
    test "validates location within correct inventory" do
      user = create_test_user(%{name: "Validator", role: "admin"})
      {:ok, inv1} = Inventory.create_inventory(%{name: "Inv1", user_id: user.id})
      {:ok, inv2} = Inventory.create_inventory(%{name: "Inv2", user_id: user.id})

      {:ok, _shelf} = Inventory.create_shelf_with_bins(inv1.id, %{code: "A"}, 1)

      assert {:ok, :exists, _location} = Inventory.validate_location_code(inv1.id, "A-1")
      assert {:error, :shelf_not_found, "A"} = Inventory.validate_location_code(inv2.id, "A-1")
    end
  end
end
