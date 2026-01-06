defmodule InventoryLocator.InventoryTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory

  describe "shelves" do
    @valid_attrs %{code: "A", name: "Shelf A", description: "Top shelf"}
    @update_attrs %{code: "B", name: "Shelf B", description: "Second shelf"}
    @invalid_attrs %{code: nil}

    test "list_shelves/0 returns all shelves" do
      {:ok, shelf} = Inventory.create_shelf(@valid_attrs)
      assert Inventory.list_shelves() == [shelf]
    end

    test "get_shelf!/1 returns the shelf with given id" do
      {:ok, shelf} = Inventory.create_shelf(@valid_attrs)
      assert Inventory.get_shelf!(shelf.id) == shelf
    end

    test "create_shelf/1 with valid data creates a shelf" do
      assert {:ok, shelf} = Inventory.create_shelf(@valid_attrs)
      assert shelf.code == "A"
      assert shelf.name == "Shelf A"
      assert shelf.description == "Top shelf"
    end

    test "create_shelf/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_shelf(@invalid_attrs)
    end

    test "create_shelf/1 with duplicate code returns error changeset" do
      {:ok, _shelf} = Inventory.create_shelf(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Inventory.create_shelf(@valid_attrs)
    end

    test "update_shelf/2 with valid data updates the shelf" do
      {:ok, shelf} = Inventory.create_shelf(@valid_attrs)
      assert {:ok, updated_shelf} = Inventory.update_shelf(shelf, @update_attrs)
      assert updated_shelf.code == "B"
      assert updated_shelf.name == "Shelf B"
    end

    test "update_shelf/2 with invalid data returns error changeset" do
      {:ok, shelf} = Inventory.create_shelf(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Inventory.update_shelf(shelf, @invalid_attrs)
      assert shelf == Inventory.get_shelf!(shelf.id)
    end

    test "delete_shelf/1 deletes the shelf" do
      {:ok, shelf} = Inventory.create_shelf(@valid_attrs)
      assert {:ok, _} = Inventory.delete_shelf(shelf)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_shelf!(shelf.id) end
    end

    test "change_shelf/1 returns a shelf changeset" do
      {:ok, shelf} = Inventory.create_shelf(@valid_attrs)
      assert %Ecto.Changeset{} = Inventory.change_shelf(shelf)
    end
  end

  describe "bins" do
    setup do
      {:ok, shelf} = Inventory.create_shelf(%{code: "A"})
      %{shelf: shelf}
    end

    @valid_attrs %{code: "3", name: "Bin 3"}
    @update_attrs %{code: "4", name: "Bin 4"}
    @invalid_attrs %{code: nil}

    test "list_bins/0 returns all bins", %{shelf: shelf} do
      {:ok, bin} = Inventory.create_bin(Map.put(@valid_attrs, :shelf_id, shelf.id))
      assert Inventory.list_bins() == [bin]
    end

    test "get_bin!/1 returns the bin with given id", %{shelf: shelf} do
      {:ok, bin} = Inventory.create_bin(Map.put(@valid_attrs, :shelf_id, shelf.id))
      assert Inventory.get_bin!(bin.id) == bin
    end

    test "create_bin/1 with valid data creates a bin", %{shelf: shelf} do
      attrs = Map.put(@valid_attrs, :shelf_id, shelf.id)
      assert {:ok, bin} = Inventory.create_bin(attrs)
      assert bin.code == "3"
      assert bin.name == "Bin 3"
      assert bin.shelf_id == shelf.id
    end

    test "create_bin/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_bin(@invalid_attrs)
    end

    test "create_bin/1 with duplicate shelf_id+code returns error changeset", %{shelf: shelf} do
      attrs = Map.put(@valid_attrs, :shelf_id, shelf.id)
      {:ok, _bin} = Inventory.create_bin(attrs)
      assert {:error, %Ecto.Changeset{}} = Inventory.create_bin(attrs)
    end

    test "update_bin/2 with valid data updates the bin", %{shelf: shelf} do
      {:ok, bin} = Inventory.create_bin(Map.put(@valid_attrs, :shelf_id, shelf.id))
      assert {:ok, updated_bin} = Inventory.update_bin(bin, @update_attrs)
      assert updated_bin.code == "4"
      assert updated_bin.name == "Bin 4"
    end

    test "delete_bin/1 deletes the bin", %{shelf: shelf} do
      {:ok, bin} = Inventory.create_bin(Map.put(@valid_attrs, :shelf_id, shelf.id))
      assert {:ok, _} = Inventory.delete_bin(bin)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_bin!(bin.id) end
    end
  end

  describe "cells" do
    setup do
      {:ok, shelf} = Inventory.create_shelf(%{code: "A"})
      {:ok, bin} = Inventory.create_bin(%{code: "3", shelf_id: shelf.id})
      %{shelf: shelf, bin: bin}
    end

    @valid_attrs %{code: "1", name: "Cell 1"}
    @update_attrs %{code: "2", name: "Cell 2"}
    @invalid_attrs %{code: nil}

    test "list_cells/0 returns all cells", %{bin: bin} do
      {:ok, cell} = Inventory.create_cell(Map.put(@valid_attrs, :bin_id, bin.id))
      assert Inventory.list_cells() == [cell]
    end

    test "get_cell!/1 returns the cell with given id", %{bin: bin} do
      {:ok, cell} = Inventory.create_cell(Map.put(@valid_attrs, :bin_id, bin.id))
      assert Inventory.get_cell!(cell.id) == cell
    end

    test "create_cell/1 with valid data creates a cell", %{bin: bin} do
      attrs = Map.put(@valid_attrs, :bin_id, bin.id)
      assert {:ok, cell} = Inventory.create_cell(attrs)
      assert cell.code == "1"
      assert cell.name == "Cell 1"
      assert cell.bin_id == bin.id
    end

    test "create_cell/1 with duplicate bin_id+code returns error changeset", %{bin: bin} do
      attrs = Map.put(@valid_attrs, :bin_id, bin.id)
      {:ok, _cell} = Inventory.create_cell(attrs)
      assert {:error, %Ecto.Changeset{}} = Inventory.create_cell(attrs)
    end

    test "delete_cell/1 deletes the cell", %{bin: bin} do
      {:ok, cell} = Inventory.create_cell(Map.put(@valid_attrs, :bin_id, bin.id))
      assert {:ok, _} = Inventory.delete_cell(cell)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_cell!(cell.id) end
    end
  end

  describe "locations" do
    setup do
      {:ok, shelf} = Inventory.create_shelf(%{code: "A"})
      {:ok, bin} = Inventory.create_bin(%{code: "3", shelf_id: shelf.id})
      {:ok, cell} = Inventory.create_cell(%{code: "1", bin_id: bin.id})
      %{shelf: shelf, bin: bin, cell: cell}
    end

    test "list_locations/0 returns all locations", %{cell: cell} do
      attrs = %{
        full_code: "A3-1",
        cell_id: cell.id
      }

      {:ok, location} = Inventory.create_location(attrs)
      assert Inventory.list_locations() == [location]
    end

    test "create_location/1 with valid data creates a location", %{cell: cell} do
      attrs = %{
        full_code: "A3-1",
        cell_id: cell.id
      }

      assert {:ok, location} = Inventory.create_location(attrs)
      assert location.full_code == "A3-1"
      assert location.cell_id == cell.id
    end

    test "create_location/1 with duplicate cell_id returns error changeset", %{cell: cell} do
      attrs = %{
        full_code: "A3-1",
        cell_id: cell.id
      }

      {:ok, _location} = Inventory.create_location(attrs)
      assert {:error, %Ecto.Changeset{}} = Inventory.create_location(attrs)
    end

    test "create_location/1 without required fields returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_location(%{})
    end

    test "delete_location/1 deletes the location", %{cell: cell} do
      attrs = %{
        full_code: "A3-1",
        cell_id: cell.id
      }

      {:ok, location} = Inventory.create_location(attrs)
      assert {:ok, _} = Inventory.delete_location(location)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_location!(location.id) end
    end
  end

  describe "item_types" do
    setup do
      {:ok, shelf} = Inventory.create_shelf(%{code: "A"})
      {:ok, bin} = Inventory.create_bin(%{code: "3", shelf_id: shelf.id})
      {:ok, cell} = Inventory.create_cell(%{code: "1", bin_id: bin.id})

      {:ok, location} =
        Inventory.create_location(%{
          full_code: "A3-1",
          cell_id: cell.id
        })

      %{location: location}
    end

    @valid_attrs %{
      name: "M5 Hex Bolts",
      description: "Stainless steel hex bolts",
      manufacturer: "McMaster-Carr",
      model: "91290A115",
      quantity: 50
    }
    @update_attrs %{name: "M6 Hex Bolts", quantity: 25}
    @invalid_attrs %{name: nil}

    test "list_item_types/0 returns all item_types", %{location: location} do
      {:ok, item_type} =
        Inventory.create_item_type(Map.put(@valid_attrs, :location_id, location.id))

      assert Inventory.list_item_types() == [item_type]
    end

    test "get_item_type!/1 returns the item_type with given id", %{location: location} do
      {:ok, item_type} =
        Inventory.create_item_type(Map.put(@valid_attrs, :location_id, location.id))

      assert Inventory.get_item_type!(item_type.id) == item_type
    end

    test "create_item_type/1 with valid data creates an item_type", %{location: location} do
      attrs = Map.put(@valid_attrs, :location_id, location.id)
      assert {:ok, item_type} = Inventory.create_item_type(attrs)
      assert item_type.name == "M5 Hex Bolts"
      assert item_type.description == "Stainless steel hex bolts"
      assert item_type.manufacturer == "McMaster-Carr"
      assert item_type.model == "91290A115"
      assert item_type.quantity == 50
    end

    test "create_item_type/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_item_type(@invalid_attrs)
    end

    test "create_item_type/1 with duplicate location_id returns error changeset", %{
      location: location
    } do
      attrs = Map.put(@valid_attrs, :location_id, location.id)
      {:ok, _item_type} = Inventory.create_item_type(attrs)
      assert {:error, %Ecto.Changeset{}} = Inventory.create_item_type(attrs)
    end

    test "create_item_type/1 with quantity <= 0 returns error changeset", %{location: location} do
      attrs = Map.put(@valid_attrs, :location_id, location.id) |> Map.put(:quantity, 0)
      assert {:error, %Ecto.Changeset{}} = Inventory.create_item_type(attrs)
    end

    test "update_item_type/2 with valid data updates the item_type", %{location: location} do
      {:ok, item_type} =
        Inventory.create_item_type(Map.put(@valid_attrs, :location_id, location.id))

      assert {:ok, updated} = Inventory.update_item_type(item_type, @update_attrs)
      assert updated.name == "M6 Hex Bolts"
      assert updated.quantity == 25
    end

    test "delete_item_type/1 deletes the item_type", %{location: location} do
      {:ok, item_type} =
        Inventory.create_item_type(Map.put(@valid_attrs, :location_id, location.id))

      assert {:ok, _} = Inventory.delete_item_type(item_type)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_item_type!(item_type.id) end
    end
  end
end
