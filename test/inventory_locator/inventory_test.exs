defmodule InventoryLocator.InventoryTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Cell
  alias InventoryLocator.Inventory.LocationCode
  alias InventoryLocator.Inventory.Shelf

  setup do
    inventory = create_test_inventory()
    %{inventory: inventory}
  end

  describe "create_item_with_location/5" do
    test "creates location hierarchy automatically", %{inventory: inventory} do
      location_code = "A-3-1"

      assert {:ok, item} =
               Inventory.create_item_with_location(
                 inventory.id,
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

    test "allows multiple items at same location (co-location)", %{inventory: inventory} do
      location_code = "A-3-1"

      assert {:ok, item1} =
               Inventory.create_item_with_location(inventory.id, location_code, "First Item", 5, "First")

      assert {:ok, item2} =
               Inventory.create_item_with_location(inventory.id, location_code, "Second Item", 3, "Second")

      item1 = Repo.preload(item1, :location)
      item2 = Repo.preload(item2, :location)
      assert item1.location.id == item2.location.id
    end

    test "returns error for invalid location format", %{inventory: inventory} do
      assert {:error, :invalid_format} =
               Inventory.create_item_with_location(inventory.id, "invalid", "Item", 1, "Desc")

      assert {:error, :invalid_format} =
               Inventory.create_item_with_location(inventory.id, "A-1", "Item", 1, "Desc")

      assert {:error, :invalid_format} =
               Inventory.create_item_with_location(inventory.id, "A3-1", "Item", 1, "Desc")
    end
  end

  describe "list_shelves_with_hierarchy/1" do
    test "preloads full hierarchy", %{inventory: inventory} do
      location_code = "A-1-1"
      {:ok, item} = Inventory.create_item_with_location(inventory.id, location_code, "Test", 1, "Desc")
      item = Repo.preload(item, :location)

      [result] = Inventory.list_shelves_with_hierarchy(inventory.id)

      assert result.code == LocationCode.shelf_code!(location_code)
      assert Ecto.assoc_loaded?(result.bins)
      assert length(result.bins) == 1
      assert Ecto.assoc_loaded?(hd(result.bins).cells)
      assert length(hd(result.bins).cells) == 1

      first_cell = hd(hd(result.bins).cells)
      assert Ecto.assoc_loaded?(first_cell.location)
      assert first_cell.location.id == item.location.id
    end

    test "returns empty list when no shelves exist", %{inventory: inventory} do
      assert Inventory.list_shelves_with_hierarchy(inventory.id) == []
    end

    test "preloads item_types association", %{inventory: inventory} do
      location_code = "A-1-1"
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, location_code, "Test Item", 5, "Desc")

      [shelf_result] = Inventory.list_shelves_with_hierarchy(inventory.id)
      bin_result = hd(shelf_result.bins)
      cell_result = hd(bin_result.cells)
      location_result = cell_result.location

      assert Ecto.assoc_loaded?(location_result.item_types)
      assert length(location_result.item_types) == 1
      assert hd(location_result.item_types).name == "Test Item"
    end
  end

  describe "delete_empty_location/1" do
    test "deletes empty location", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Test", 1, "Desc")
      item = Repo.preload(item, :location)
      Inventory.delete_item_type(item)

      assert {:ok, _} = Inventory.delete_empty_location(item.location.id)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_location!(item.location.id) end
    end

    test "refuses to delete occupied location", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Test", 1, "Desc")
      item = Repo.preload(item, :location)

      assert {:error, :occupied} = Inventory.delete_empty_location(item.location.id)
      assert Inventory.get_location!(item.location.id)
    end

    test "cascade deletes cell, bin, and shelf when they become empty", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "Q-3-1", "Test", 1, "Desc")
      item = Repo.preload(item, location: [cell: [bin: :shelf]])

      location_id = item.location.id
      cell_id = item.location.cell.id
      bin_id = item.location.cell.bin.id
      shelf_id = item.location.cell.bin.shelf.id

      # Delete item, making location empty
      Inventory.delete_item_type(item)

      # Delete empty location - should cascade to cell, bin, shelf
      assert {:ok, _} = Inventory.delete_empty_location(location_id)

      # Verify all were deleted
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_location!(location_id) end
      assert_raise Ecto.NoResultsError, fn -> Repo.get!(Cell, cell_id) end
      assert_raise Ecto.NoResultsError, fn -> Repo.get!(Bin, bin_id) end
      assert_raise Ecto.NoResultsError, fn -> Repo.get!(Shelf, shelf_id) end
    end

    test "does not delete bin when other cells exist", %{inventory: inventory} do
      {:ok, item1} = Inventory.create_item_with_location(inventory.id, "Y-8-3", "Item 1", 1, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "Y-8-4", "Item 2", 1, "Desc")

      item1 = Repo.preload(item1, location: [cell: [bin: :shelf]])
      bin_id = item1.location.cell.bin.id

      # Delete item1, making its location empty
      Inventory.delete_item_type(item1)
      assert {:ok, _} = Inventory.delete_empty_location(item1.location.id)

      # Bin should still exist because cell 4 still has a location
      assert Repo.get!(Bin, bin_id)
    end

    test "does not delete shelf when other bins exist", %{inventory: inventory} do
      {:ok, item1} = Inventory.create_item_with_location(inventory.id, "X-7-2", "Item 1", 1, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "X-8-2", "Item 2", 1, "Desc")

      item1 = Repo.preload(item1, location: [cell: [bin: :shelf]])
      shelf_id = item1.location.cell.bin.shelf.id

      # Delete item1, making its location and bin empty
      Inventory.delete_item_type(item1)
      assert {:ok, _} = Inventory.delete_empty_location(item1.location.id)

      # Shelf should still exist because bin 8 still has items
      assert Repo.get!(Shelf, shelf_id)
    end
  end

  describe "count_locations_by_occupancy/1" do
    test "returns zero counts when no locations exist", %{inventory: inventory} do
      result = Inventory.count_locations_by_occupancy(inventory.id)
      assert result.occupied == 0
      assert result.empty == 0
    end

    test "counts empty locations", %{inventory: inventory} do
      {:ok, item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 1, "Test")
      {:ok, item2} = Inventory.create_item_with_location(inventory.id, "A-2-1", "Item 2", 1, "Test")

      Inventory.delete_item_type(item1)
      Inventory.delete_item_type(item2)

      result = Inventory.count_locations_by_occupancy(inventory.id)
      assert result.occupied == 0
      assert result.empty == 2
    end

    test "counts occupied locations", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Test Item", 1, "Test")

      result = Inventory.count_locations_by_occupancy(inventory.id)
      assert result.occupied == 1
      assert result.empty == 0
    end

    test "counts mix of occupied and empty locations", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 1, "Test")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "A-2-1", "Item 2", 2, "Test")
      {:ok, item3} = Inventory.create_item_with_location(inventory.id, "A-1-2", "Item 3", 3, "Test")
      Inventory.delete_item_type(item3)

      result = Inventory.count_locations_by_occupancy(inventory.id)
      assert result.occupied == 2
      assert result.empty == 1
    end
  end

  describe "search_items/3" do
    test "returns empty list when query is empty string", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Screws", 10, "M3")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "B-1-1", "Nails", 20, "Galvanized")

      results = Inventory.search_items(inventory.id, "", [])
      assert results == []
    end

    test "finds items with exact match using fuzzy search", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "M3 Screws", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "B-1-1", "Nails", 20, "Desc")

      results = Inventory.search_items(inventory.id, "screws", [])
      assert length(results) == 1
      assert hd(results).name == "M3 Screws"
    end

    test "handles typos with fuzzy matching", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "M3 Screws", 10, "Desc")

      results = Inventory.search_items(inventory.id, "scres", [])
      assert length(results) == 1
      assert hd(results).name == "M3 Screws"
    end

    test "orders by similarity score (most relevant first)", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Screws", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "B-1-1", "M3 Screws", 20, "Desc")

      results = Inventory.search_items(inventory.id, "screws", [])
      assert length(results) == 2
      assert hd(results).name == "Screws"
    end

    test "preloads location with full hierarchy", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Test Item", 10, "Desc")

      results = Inventory.search_items(inventory.id, "test", [])
      assert length(results) == 1

      item = hd(results)
      assert Ecto.assoc_loaded?(item.location)
      assert Ecto.assoc_loaded?(item.location.cell)
      assert Ecto.assoc_loaded?(item.location.cell.bin)
      assert Ecto.assoc_loaded?(item.location.cell.bin.shelf)
    end

    test "filters by missing manufacturer", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 10, "Desc")

      results = Inventory.search_items(inventory.id, "", filters: [:manufacturer])
      assert length(results) == 1
      assert hd(results).name == "Item 1"
    end

    test "filters by missing model", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 10, "Desc")

      results = Inventory.search_items(inventory.id, "", filters: [:model])
      assert length(results) == 1
    end

    test "filters by missing description", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 10, "Desc")
      item = Repo.preload(item, :location)

      Inventory.delete_item_type(item)

      {:ok, _item2} =
        Inventory.create_item_with_location(inventory.id, item.location.full_code, "Item 2", 5, nil)

      results = Inventory.search_items(inventory.id, "", filters: [:description])
      assert length(results) == 1
      assert hd(results).name == "Item 2"
    end

    test "filters with multiple criteria use OR logic", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "B-1-1", "Item 2", 20, "Desc")

      results = Inventory.search_items(inventory.id, "", filters: [:manufacturer, :model])
      assert length(results) == 2
    end

    test "combines search query with filters", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Screws", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "B-1-1", "Nails", 20, "Desc")

      results = Inventory.search_items(inventory.id, "screw", filters: [:manufacturer])
      assert length(results) == 1
      assert hd(results).name == "Screws"
    end

    test "hides archived items by default", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Active Item", 10, "Desc")

      results = Inventory.search_items(inventory.id, "item", [])
      assert length(results) == 1
      assert hd(results).archived == false
    end

    test "shows archived items when show_archived is true", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Active Item", 10, "Desc")

      results = Inventory.search_items(inventory.id, "item", show_archived: true)
      assert length(results) == 1
    end

    test "filters exclude archived items even when missing fields", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 10, "Desc")

      results = Inventory.search_items(inventory.id, "", filters: [:manufacturer])
      assert length(results) == 1
      assert hd(results).archived == false
    end

    test "orders active items before archived items when using filters", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Active Item", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "B-1-1", "Zulu Item", 5, "Desc")

      results = Inventory.search_items(inventory.id, "", filters: [:manufacturer])
      assert length(results) == 2
      assert Enum.at(results, 0).name == "Active Item"
      assert Enum.at(results, 1).name == "Zulu Item"
      assert Enum.all?(results, &(&1.archived == false))
    end
  end

  describe "multi-item locations" do
    test "archived items don't prevent location deletion", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Test", 5, "Desc")
      item = Repo.preload(item, :location)

      {:ok, _archived} = Inventory.archive_item_type(item)

      assert {:ok, _} = Inventory.delete_empty_location(item.location.id)
    end

    test "active items prevent location deletion even with archived items present", %{inventory: inventory} do
      {:ok, item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Active", 5, "Desc")
      {:ok, item2} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Archived", 3, "Desc")

      item1 = Repo.preload(item1, :location)
      {:ok, _} = Inventory.archive_item_type(item2)

      assert {:error, :occupied} = Inventory.delete_empty_location(item1.location.id)
    end

    test "ensure_location_with_code returns item count for occupied locations", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 5, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 2", 3, "Desc")

      assert {:ok, location, 2} = Inventory.ensure_location_with_code(inventory.id, "A-1-1")
      assert location.full_code == "A-1-1"
    end

    test "count_locations_by_occupancy counts location once even with multiple items", %{inventory: inventory} do
      {:ok, _item1} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 1", 5, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Item 2", 3, "Desc")
      {:ok, _item3} = Inventory.create_item_with_location(inventory.id, "A-1-2", "Item 3", 2, "Desc")

      result = Inventory.count_locations_by_occupancy(inventory.id)
      assert result.occupied == 2
      assert result.empty == 0
    end
  end

  describe "archive_item_type/1" do
    test "keeps location_id when archiving", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Test", 5, "Desc")
      item = Repo.preload(item, :location)
      original_location_id = item.location_id

      {:ok, archived} = Inventory.archive_item_type(item)

      assert archived.archived == true
      assert archived.quantity == 0
      assert archived.location_id == original_location_id
    end

    test "archived items remain searchable with show_archived option", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Test Item", 5, "Desc")
      {:ok, _archived} = Inventory.archive_item_type(item)

      results = Inventory.search_items(inventory.id, "test", show_archived: true)
      assert length(results) == 1
      assert hd(results).archived == true
    end
  end

  describe "create_shelf_with_bins/3" do
    test "creates shelf with specified number of bins", %{inventory: inventory} do
      assert {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "TEST"}, 3)

      shelf = Repo.preload(shelf, bins: :cells)
      assert shelf.code == "TEST"
      assert length(shelf.bins) == 3
      assert shelf.bins |> Enum.map(& &1.code) |> Enum.sort() == ["1", "2", "3"]
    end

    test "each bin starts with cell 1 and a location", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "TEST"}, 2)

      shelf = Repo.preload(shelf, bins: [cells: :location])

      for bin <- shelf.bins do
        assert length(bin.cells) == 1
        assert hd(bin.cells).code == "1"
        assert hd(bin.cells).location
        assert hd(bin.cells).location.full_code == "TEST-#{bin.code}-1"
      end
    end

    test "returns error for duplicate shelf code", %{inventory: inventory} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "DUPE"}, 1)

      assert {:error, changeset} = Inventory.create_shelf_with_bins(inventory.id, %{code: "DUPE"}, 1)
      assert changeset.errors[:code]
    end

    test "returns error for invalid shelf code", %{inventory: inventory} do
      assert {:error, _changeset} = Inventory.create_shelf_with_bins(inventory.id, %{code: "123"}, 1)
      assert {:error, _changeset} = Inventory.create_shelf_with_bins(inventory.id, %{code: "_bad"}, 1)
    end
  end

  describe "add_bin_to_shelf/1" do
    test "adds bin with next sequential code", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "TEST"}, 2)

      {:ok, new_bin} = Inventory.add_bin_to_shelf(shelf)

      assert new_bin.code == "3"
      assert new_bin.shelf_id == shelf.id
    end

    test "new bin includes cell 1 with location", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "TEST"}, 1)

      {:ok, new_bin} = Inventory.add_bin_to_shelf(shelf)
      new_bin = Repo.preload(new_bin, cells: :location)

      assert length(new_bin.cells) == 1
      assert hd(new_bin.cells).code == "1"
      assert hd(new_bin.cells).location.full_code == "TEST-2-1"
    end
  end

  describe "add_cell_to_bin/1" do
    test "adds cell with next sequential code", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "TEST"}, 1)
      shelf = Repo.preload(shelf, :bins)
      bin = hd(shelf.bins)

      {:ok, new_cell} = Inventory.add_cell_to_bin(bin)

      assert new_cell.code == "2"
      assert new_cell.bin_id == bin.id
    end

    test "new cell includes location with correct full_code", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "TEST"}, 1)
      shelf = Repo.preload(shelf, :bins)
      bin = hd(shelf.bins)

      {:ok, new_cell} = Inventory.add_cell_to_bin(bin)
      new_cell = Repo.preload(new_cell, :location)

      assert new_cell.location.full_code == "TEST-1-2"
    end
  end

  describe "rename_shelf/3" do
    test "updates shelf code", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "OLD"}, 1)

      {:ok, updated} = Inventory.rename_shelf(inventory.id, shelf, "NEW")

      assert updated.code == "NEW"
    end

    test "updates all location full_codes", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "OLD"}, 2)
      shelf = Repo.preload(shelf, :bins)
      Inventory.add_cell_to_bin(hd(shelf.bins))

      {:ok, _updated} = Inventory.rename_shelf(inventory.id, shelf, "NEW")

      locations = Repo.all(from(l in Inventory.Location, order_by: l.full_code))
      codes = Enum.map(locations, & &1.full_code)

      assert "NEW-1-1" in codes
      assert "NEW-1-2" in codes
      assert "NEW-2-1" in codes
      refute Enum.any?(codes, &String.starts_with?(&1, "OLD"))
    end

    test "returns error for invalid code format", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "TEST"}, 1)

      assert {:error, :invalid_code} = Inventory.rename_shelf(inventory.id, shelf, "123")
      assert {:error, :invalid_code} = Inventory.rename_shelf(inventory.id, shelf, "_bad")
    end

    test "returns error if new code already exists", %{inventory: inventory} do
      {:ok, shelf1} = Inventory.create_shelf_with_bins(inventory.id, %{code: "FIRST"}, 1)
      {:ok, _shelf2} = Inventory.create_shelf_with_bins(inventory.id, %{code: "SECOND"}, 1)

      assert {:error, :code_exists} = Inventory.rename_shelf(inventory.id, shelf1, "SECOND")
    end

    test "succeeds when renaming to same code (no-op)", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "SAME"}, 1)

      assert {:ok, unchanged} = Inventory.rename_shelf(inventory.id, shelf, "SAME")
      assert unchanged.code == "SAME"
    end

    test "normalizes code to uppercase", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "OLD"}, 1)

      {:ok, updated} = Inventory.rename_shelf(inventory.id, shelf, "new")

      assert updated.code == "NEW"
    end
  end

  describe "delete_empty_shelf/1" do
    test "deletes shelf with no items", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "EMPTY"}, 2)

      assert {:ok, _deleted} = Inventory.delete_empty_shelf(shelf)

      assert Repo.get(Shelf, shelf.id) == nil
      assert Repo.all(from(b in Bin, where: b.shelf_id == ^shelf.id)) == []
    end

    test "deletes all bins, cells, and locations", %{inventory: inventory} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "EMPTY"}, 2)
      shelf = Repo.preload(shelf, :bins)
      Inventory.add_cell_to_bin(hd(shelf.bins))

      location_count_before = Repo.aggregate(Inventory.Location, :count)
      assert location_count_before == 3

      {:ok, _deleted} = Inventory.delete_empty_shelf(shelf)

      assert Repo.aggregate(Inventory.Location, :count) == 0
      assert Repo.aggregate(Cell, :count) == 0
      assert Repo.aggregate(Bin, :count) == 0
    end

    test "returns error when shelf has active items", %{inventory: inventory} do
      {:ok, _item} = Inventory.create_item_with_location(inventory.id, "OCCUPIED-1-1", "Test", 1, "Desc")
      shelf = Repo.get_by!(Shelf, code: "OCCUPIED")

      assert {:error, :has_items} = Inventory.delete_empty_shelf(shelf)
      assert Repo.get(Shelf, shelf.id)
    end

    test "succeeds when shelf only has archived items", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "ARCHIVED-1-1", "Test", 1, "Desc")
      Inventory.archive_item_type(item)
      shelf = Repo.get_by!(Shelf, code: "ARCHIVED")

      assert {:ok, _deleted} = Inventory.delete_empty_shelf(shelf)
      assert Repo.get(Shelf, shelf.id) == nil
    end

    test "clears location_id from archived items before deletion", %{inventory: inventory} do
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "CLEAR-1-1", "Test", 1, "Desc")
      {:ok, archived_item} = Inventory.archive_item_type(item)
      shelf = Repo.get_by!(Shelf, code: "CLEAR")

      {:ok, _deleted} = Inventory.delete_empty_shelf(shelf)

      reloaded_item = Repo.get!(Inventory.ItemType, archived_item.id)
      assert reloaded_item.location_id == nil
    end
  end
end
