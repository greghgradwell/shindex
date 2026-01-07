defmodule InventoryLocator.Inventory.LocationParser.ValidateTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.LocationParser
  alias InventoryLocator.Inventory.LocationParser.{Status, Missing}

  describe "validate/1" do
    test "returns needs_creation with all missing when shelf does not exist" do
      parsed = %{shelf_code: "Z", bin_code: "99", cell_code: "88"}

      assert {:ok, result} = LocationParser.validate(parsed)
      assert result.status == Status.needs_creation()

      assert result.missing == [
               Missing.shelf(),
               Missing.bin(),
               Missing.cell(),
               Missing.location()
             ]

      assert result.location == nil
      assert result.item_type == nil
    end

    test "returns needs_creation with bin, cell, location missing when only shelf exists" do
      Inventory.create_shelf!(%{code: "A"})
      parsed = %{shelf_code: "A", bin_code: "99", cell_code: "88"}

      assert {:ok, result} = LocationParser.validate(parsed)
      assert result.status == Status.needs_creation()
      assert result.missing == [Missing.bin(), Missing.cell(), Missing.location()]
      assert result.location == nil
      assert result.item_type == nil
    end

    test "returns needs_creation with cell, location missing when shelf and bin exist" do
      shelf = Inventory.create_shelf!(%{code: "A"})
      Inventory.create_bin!(%{code: "3", shelf_id: shelf.id})
      parsed = %{shelf_code: "A", bin_code: "3", cell_code: "88"}

      assert {:ok, result} = LocationParser.validate(parsed)
      assert result.status == Status.needs_creation()
      assert result.missing == [Missing.cell(), Missing.location()]
      assert result.location == nil
      assert result.item_type == nil
    end

    test "returns needs_creation with location missing when shelf, bin, and cell exist" do
      shelf = Inventory.create_shelf!(%{code: "A"})
      bin = Inventory.create_bin!(%{code: "3", shelf_id: shelf.id})
      Inventory.create_cell!(%{code: "1", bin_id: bin.id})
      parsed = %{shelf_code: "A", bin_code: "3", cell_code: "1"}

      assert {:ok, result} = LocationParser.validate(parsed)
      assert result.status == Status.needs_creation()
      assert result.missing == [Missing.location()]
      assert result.location == nil
      assert result.item_type == nil
    end

    test "returns exists_empty when location exists but has no item" do
      shelf = Inventory.create_shelf!(%{code: "A"})
      bin = Inventory.create_bin!(%{code: "3", shelf_id: shelf.id})
      cell = Inventory.create_cell!(%{code: "1", bin_id: bin.id})
      location = Inventory.create_location!(%{full_code: "A-3-1", cell_id: cell.id})
      parsed = %{shelf_code: "A", bin_code: "3", cell_code: "1"}

      assert {:ok, result} = LocationParser.validate(parsed)
      assert result.status == Status.exists_empty()
      assert result.missing == []
      assert result.location.id == location.id
      assert result.item_type == nil
    end

    test "returns exists_occupied when location exists and has an item" do
      shelf = Inventory.create_shelf!(%{code: "A"})
      bin = Inventory.create_bin!(%{code: "3", shelf_id: shelf.id})
      cell = Inventory.create_cell!(%{code: "1", bin_id: bin.id})
      location = Inventory.create_location!(%{full_code: "A-3-1", cell_id: cell.id})

      item_type =
        Inventory.create_item_type!(%{
          name: "Test Item",
          quantity: 10,
          location_id: location.id
        })

      parsed = %{shelf_code: "A", bin_code: "3", cell_code: "1"}

      assert {:ok, result} = LocationParser.validate(parsed)
      assert result.status == Status.exists_occupied()
      assert result.missing == []
      assert result.location.id == location.id
      assert result.item_type.id == item_type.id
    end
  end

  describe "parse_and_validate/1" do
    test "returns error for invalid format" do
      assert {:error, :invalid_format} = LocationParser.parse_and_validate("invalid")
      assert {:error, :invalid_format} = LocationParser.parse_and_validate("a-b")
      assert {:error, :invalid_format} = LocationParser.parse_and_validate("tall-bench-3-1")
    end

    test "returns merged result for valid code with no existing entities" do
      assert {:ok, result} = LocationParser.parse_and_validate("Z-99-88")
      assert result.shelf_code == "Z"
      assert result.bin_code == "99"
      assert result.cell_code == "88"
      assert result.status == Status.needs_creation()

      assert result.missing == [
               Missing.shelf(),
               Missing.bin(),
               Missing.cell(),
               Missing.location()
             ]

      assert result.location == nil
      assert result.item_type == nil
    end

    test "returns merged result for valid code with existing empty location" do
      shelf = Inventory.create_shelf!(%{code: "B"})
      bin = Inventory.create_bin!(%{code: "5", shelf_id: shelf.id})
      cell = Inventory.create_cell!(%{code: "2", bin_id: bin.id})
      location = Inventory.create_location!(%{full_code: "B-5-2", cell_id: cell.id})

      assert {:ok, result} = LocationParser.parse_and_validate("b-5-2")
      assert result.shelf_code == "B"
      assert result.bin_code == "5"
      assert result.cell_code == "2"
      assert result.status == Status.exists_empty()
      assert result.missing == []
      assert result.location.id == location.id
      assert result.item_type == nil
    end

    test "returns merged result for valid code with occupied location" do
      shelf = Inventory.create_shelf!(%{code: "C"})
      bin = Inventory.create_bin!(%{code: "7", shelf_id: shelf.id})
      cell = Inventory.create_cell!(%{code: "3", bin_id: bin.id})
      location = Inventory.create_location!(%{full_code: "C-7-3", cell_id: cell.id})

      item_type =
        Inventory.create_item_type!(%{
          name: "Occupied Item",
          quantity: 5,
          location_id: location.id
        })

      assert {:ok, result} = LocationParser.parse_and_validate("C-7-3")
      assert result.status == Status.exists_occupied()
      assert result.item_type.id == item_type.id
    end

    test "handles multi-character shelf names" do
      shelf = Inventory.create_shelf!(%{code: "TALL_WORKBENCH"})
      bin = Inventory.create_bin!(%{code: "12", shelf_id: shelf.id})
      cell = Inventory.create_cell!(%{code: "5", bin_id: bin.id})
      location = Inventory.create_location!(%{full_code: "TALL_WORKBENCH-12-5", cell_id: cell.id})

      assert {:ok, result} = LocationParser.parse_and_validate("tall_workbench-12-5")
      assert result.shelf_code == "TALL_WORKBENCH"
      assert result.bin_code == "12"
      assert result.cell_code == "5"
      assert result.status == Status.exists_empty()
      assert result.location.id == location.id
    end
  end
end
