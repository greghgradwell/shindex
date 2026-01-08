defmodule InventoryLocator.InventoryTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.LocationCode

  describe "create_item_with_location/4" do
    test "creates location hierarchy automatically" do
      location_code = "A-3-1"

      assert {:ok, item} =
               Inventory.create_item_with_location(
                 location_code,
                 "Test Item",
                 5,
                 "Test description"
               )

      item = Repo.preload(item, location: [cell: [bin: :shelf]])
      assert item.location.full_code == location_code
      assert item.location.cell.code == LocationCode.cell_code!(location_code)
      assert item.location.cell.bin.code == LocationCode.bin_code!(location_code)
      assert item.location.cell.bin.shelf.code == LocationCode.shelf_code!(location_code)
    end

    test "allows multiple items at same location (co-location)" do
      location_code = "A-3-1"

      assert {:ok, item1} =
               Inventory.create_item_with_location(location_code, "First Item", 5, "First")

      assert {:ok, item2} =
               Inventory.create_item_with_location(location_code, "Second Item", 3, "Second")

      item1 = Repo.preload(item1, :location)
      item2 = Repo.preload(item2, :location)
      assert item1.location.id == item2.location.id
    end

    test "returns error for invalid location format" do
      assert {:error, :invalid_format} =
               Inventory.create_item_with_location("invalid", "Item", 1, "Desc")

      assert {:error, :invalid_format} =
               Inventory.create_item_with_location("A-1", "Item", 1, "Desc")

      assert {:error, :invalid_format} =
               Inventory.create_item_with_location("A3-1", "Item", 1, "Desc")
    end
  end

  describe "list_shelves_with_hierarchy/0" do
    test "preloads full hierarchy" do
      location_code = "A-1-0"
      {:ok, item} = Inventory.create_item_with_location(location_code, "Test", 1, "Desc")
      item = Repo.preload(item, :location)

      [result] = Inventory.list_shelves_with_hierarchy()

      assert result.code == LocationCode.shelf_code!(location_code)
      assert Ecto.assoc_loaded?(result.bins)
      assert length(result.bins) == 1
      assert Ecto.assoc_loaded?(hd(result.bins).cells)
      assert length(hd(result.bins).cells) == 1

      first_cell = hd(hd(result.bins).cells)
      assert Ecto.assoc_loaded?(first_cell.location)
      assert first_cell.location.id == item.location.id
    end

    test "returns empty list when no shelves exist" do
      assert Inventory.list_shelves_with_hierarchy() == []
    end

    test "preloads item_types association" do
      location_code = "A-1-0"
      {:ok, _item} = Inventory.create_item_with_location(location_code, "Test Item", 5, "Desc")

      [shelf_result] = Inventory.list_shelves_with_hierarchy()
      bin_result = hd(shelf_result.bins)
      cell_result = hd(bin_result.cells)
      location_result = cell_result.location

      assert Ecto.assoc_loaded?(location_result.item_types)
      assert length(location_result.item_types) == 1
      assert hd(location_result.item_types).name == "Test Item"
    end
  end

  describe "delete_empty_location/1" do
    test "deletes empty location" do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test", 1, "Desc")
      item = Repo.preload(item, :location)
      Inventory.delete_item_type(item)

      assert {:ok, _} = Inventory.delete_empty_location(item.location.id)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_location!(item.location.id) end
    end

    test "refuses to delete occupied location" do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test", 1, "Desc")
      item = Repo.preload(item, :location)

      assert {:error, :occupied} = Inventory.delete_empty_location(item.location.id)
      assert Inventory.get_location!(item.location.id)
    end
  end

  describe "count_locations_by_occupancy/0" do
    test "returns zero counts when no locations exist" do
      result = Inventory.count_locations_by_occupancy()
      assert result.occupied == 0
      assert result.empty == 0
    end

    test "counts empty locations" do
      {:ok, item1} = Inventory.create_item_with_location("A-1-0", "Item 1", 1, "Test")
      {:ok, item2} = Inventory.create_item_with_location("A-1-1", "Item 2", 1, "Test")

      Inventory.delete_item_type(item1)
      Inventory.delete_item_type(item2)

      result = Inventory.count_locations_by_occupancy()
      assert result.occupied == 0
      assert result.empty == 2
    end

    test "counts occupied locations" do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Test Item", 1, "Test")

      result = Inventory.count_locations_by_occupancy()
      assert result.occupied == 1
      assert result.empty == 0
    end

    test "counts mix of occupied and empty locations" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Item 1", 1, "Test")
      {:ok, _item2} = Inventory.create_item_with_location("A-1-1", "Item 2", 2, "Test")
      {:ok, item3} = Inventory.create_item_with_location("A-1-2", "Item 3", 3, "Test")
      Inventory.delete_item_type(item3)

      result = Inventory.count_locations_by_occupancy()
      assert result.occupied == 2
      assert result.empty == 1
    end
  end

  describe "search_items/2" do
    test "returns empty list when query is empty string" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Screws", 10, "M3")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-0", "Nails", 20, "Galvanized")

      results = Inventory.search_items("", [])
      assert results == []
    end

    test "finds items with exact match using fuzzy search" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "M3 Screws", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-0", "Nails", 20, "Desc")

      results = Inventory.search_items("screws", [])
      assert length(results) == 1
      assert hd(results).name == "M3 Screws"
    end

    test "handles typos with fuzzy matching" do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "M3 Screws", 10, "Desc")

      results = Inventory.search_items("scres", [])
      assert length(results) == 1
      assert hd(results).name == "M3 Screws"
    end

    test "orders by similarity score (most relevant first)" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Screws", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-0", "M3 Screws", 20, "Desc")

      results = Inventory.search_items("screws", [])
      assert length(results) == 2
      assert hd(results).name == "Screws"
    end

    test "preloads location with full hierarchy" do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Test Item", 10, "Desc")

      results = Inventory.search_items("test", [])
      assert length(results) == 1

      item = hd(results)
      assert Ecto.assoc_loaded?(item.location)
      assert Ecto.assoc_loaded?(item.location.cell)
      assert Ecto.assoc_loaded?(item.location.cell.bin)
      assert Ecto.assoc_loaded?(item.location.cell.bin.shelf)
    end

    test "filters by missing manufacturer" do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Item 1", 10, "Desc")

      results = Inventory.search_items("", filters: [:manufacturer])
      assert length(results) == 1
      assert hd(results).name == "Item 1"
    end

    test "filters by missing model" do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Item 1", 10, "Desc")

      results = Inventory.search_items("", filters: [:model])
      assert length(results) == 1
    end

    test "filters by missing description" do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Item 1", 10, "Desc")
      item = Repo.preload(item, :location)

      Inventory.delete_item_type(item)

      {:ok, _item2} =
        Inventory.create_item_with_location(item.location.full_code, "Item 2", 5, nil)

      results = Inventory.search_items("", filters: [:description])
      assert length(results) == 1
      assert hd(results).name == "Item 2"
    end

    test "filters with multiple criteria use OR logic" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Item 1", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-0", "Item 2", 20, "Desc")

      results = Inventory.search_items("", filters: [:manufacturer, :model])
      assert length(results) == 2
    end

    test "combines search query with filters" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Screws", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-0", "Nails", 20, "Desc")

      results = Inventory.search_items("screw", filters: [:manufacturer])
      assert length(results) == 1
      assert hd(results).name == "Screws"
    end

    test "hides archived items by default" do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Active Item", 10, "Desc")

      results = Inventory.search_items("item", [])
      assert length(results) == 1
      assert hd(results).archived == false
    end

    test "shows archived items when show_archived is true" do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Active Item", 10, "Desc")

      results = Inventory.search_items("item", show_archived: true)
      assert length(results) == 1
    end

    test "filters exclude archived items even when missing fields" do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Item 1", 10, "Desc")

      results = Inventory.search_items("", filters: [:manufacturer])
      assert length(results) == 1
      assert hd(results).archived == false
    end

    test "orders active items before archived items when using filters" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Active Item", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-0", "Zulu Item", 5, "Desc")

      results = Inventory.search_items("", filters: [:manufacturer])
      assert length(results) == 2
      assert Enum.at(results, 0).name == "Active Item"
      assert Enum.at(results, 1).name == "Zulu Item"
      assert Enum.all?(results, &(&1.archived == false))
    end
  end

  describe "multi-item locations" do
    test "archived items don't prevent location deletion" do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test", 5, "Desc")
      item = Repo.preload(item, :location)

      {:ok, _archived} = Inventory.archive_item_type(item)

      assert {:ok, _} = Inventory.delete_empty_location(item.location.id)
    end

    test "active items prevent location deletion even with archived items present" do
      {:ok, item1} = Inventory.create_item_with_location("A-1-0", "Active", 5, "Desc")
      {:ok, item2} = Inventory.create_item_with_location("A-1-0", "Archived", 3, "Desc")

      item1 = Repo.preload(item1, :location)
      {:ok, _} = Inventory.archive_item_type(item2)

      assert {:error, :occupied} = Inventory.delete_empty_location(item1.location.id)
    end

    test "ensure_location_with_code returns item count for occupied locations" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Item 1", 5, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("A-1-0", "Item 2", 3, "Desc")

      assert {:ok, location, 2} = Inventory.ensure_location_with_code("A-1-0")
      assert location.full_code == "A-1-0"
    end

    test "count_locations_by_occupancy counts location once even with multiple items" do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Item 1", 5, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("A-1-0", "Item 2", 3, "Desc")
      {:ok, _item3} = Inventory.create_item_with_location("A-1-1", "Item 3", 2, "Desc")

      result = Inventory.count_locations_by_occupancy()
      assert result.occupied == 2
      assert result.empty == 0
    end
  end

  describe "archive_item_type/1" do
    test "keeps location_id when archiving" do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test", 5, "Desc")
      item = Repo.preload(item, :location)
      original_location_id = item.location_id

      {:ok, archived} = Inventory.archive_item_type(item)

      assert archived.archived == true
      assert archived.quantity == 0
      assert archived.location_id == original_location_id
    end

    test "archived items remain searchable with show_archived option" do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test Item", 5, "Desc")
      {:ok, _archived} = Inventory.archive_item_type(item)

      results = Inventory.search_items("test", show_archived: true)
      assert length(results) == 1
      assert hd(results).archived == true
    end
  end
end
