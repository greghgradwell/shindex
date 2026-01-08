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

    test "returns error for occupied location" do
      location_code = "A-3-1"

      assert {:ok, _item1} =
               Inventory.create_item_with_location(location_code, "First Item", 5, "First")

      assert {:error, :already_occupied} =
               Inventory.create_item_with_location(location_code, "Second Item", 3, "Second")
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

    test "preloads item_type association" do
      location_code = "A-1-0"
      {:ok, _item} = Inventory.create_item_with_location(location_code, "Test Item", 5, "Desc")

      [shelf_result] = Inventory.list_shelves_with_hierarchy()
      bin_result = hd(shelf_result.bins)
      cell_result = hd(bin_result.cells)
      location_result = cell_result.location

      assert Ecto.assoc_loaded?(location_result.item_type)
      assert location_result.item_type.name == "Test Item"
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
end
