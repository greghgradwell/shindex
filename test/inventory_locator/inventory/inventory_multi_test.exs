defmodule InventoryLocator.Inventory.InventoryMultiTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory

  describe "inventory isolation" do
    setup do
      {:ok, workshop} = Inventory.create_inventory(%{name: "Workshop"})
      {:ok, kitchen} = Inventory.create_inventory(%{name: "Kitchen"})
      %{workshop: workshop, kitchen: kitchen}
    end

    test "items are isolated between inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, _workshop_item} =
        Inventory.create_item_with_location(workshop.id, "A-1-1", "Workshop Screws", 10, "Desc")

      {:ok, _kitchen_item} =
        Inventory.create_item_with_location(kitchen.id, "A-1-1", "Kitchen Utensils", 5, "Desc")

      workshop_items = Inventory.list_all_items(workshop.id, show_archived: false)
      kitchen_items = Inventory.list_all_items(kitchen.id, show_archived: false)

      assert length(workshop_items) == 1
      assert hd(workshop_items).name == "Workshop Screws"

      assert length(kitchen_items) == 1
      assert hd(kitchen_items).name == "Kitchen Utensils"
    end

    test "search only returns items from specified inventory", %{workshop: workshop, kitchen: kitchen} do
      {:ok, _item1} =
        Inventory.create_item_with_location(workshop.id, "A-1-1", "Hammer", 1, "Workshop tool")

      {:ok, _item2} =
        Inventory.create_item_with_location(kitchen.id, "A-1-1", "Meat Hammer", 1, "Kitchen tool")

      workshop_results = Inventory.search_items(workshop.id, "hammer", [])
      kitchen_results = Inventory.search_items(kitchen.id, "hammer", [])

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
      {:ok, _item1} = Inventory.create_item_with_location(workshop.id, "A-1-1", "Item 1", 1, nil)
      {:ok, _item2} = Inventory.create_item_with_location(kitchen.id, "B-2-2", "Item 2", 1, nil)

      workshop_codes = Inventory.list_location_codes(workshop.id)
      kitchen_codes = Inventory.list_location_codes(kitchen.id)

      assert "A-1-1" in workshop_codes
      refute "B-2-2" in workshop_codes

      assert "B-2-2" in kitchen_codes
      refute "A-1-1" in kitchen_codes
    end

    test "occupancy stats are isolated between inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, _item1} = Inventory.create_item_with_location(workshop.id, "A-1-1", "Item 1", 1, nil)
      {:ok, _item2} = Inventory.create_item_with_location(workshop.id, "A-1-2", "Item 2", 1, nil)
      {:ok, _item3} = Inventory.create_item_with_location(kitchen.id, "B-1-1", "Item 3", 1, nil)

      workshop_stats = Inventory.count_locations_by_occupancy(workshop.id)
      kitchen_stats = Inventory.count_locations_by_occupancy(kitchen.id)

      assert workshop_stats.occupied == 2
      assert kitchen_stats.occupied == 1
    end

    test "projects are isolated between inventories", %{workshop: workshop, kitchen: kitchen} do
      {:ok, workshop_item} =
        Inventory.create_item_with_location(workshop.id, "A-1-1", "Workshop Part", 10, nil)

      {:ok, kitchen_item} =
        Inventory.create_item_with_location(kitchen.id, "A-1-1", "Kitchen Part", 5, nil)

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
      {:ok, inv1} = Inventory.create_inventory(%{name: "Inv1"})
      {:ok, inv2} = Inventory.create_inventory(%{name: "Inv2"})

      {:ok, _shelf} = Inventory.create_shelf_with_bins(inv1.id, %{code: "A"}, 1)

      assert {:ok, :exists, _location} = Inventory.validate_location_code(inv1.id, "A-1-1")
      assert {:error, :shelf_not_found, "A"} = Inventory.validate_location_code(inv2.id, "A-1-1")
    end
  end
end
