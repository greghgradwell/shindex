defmodule InventoryLocator.Inventory.LocationParser.ParseTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory.LocationParser

  describe "parse/1" do
    test "parses valid location code with uppercase shelf" do
      assert {:ok, %{shelf_code: "A", bin_code: "3", cell_code: "1"}} =
               LocationParser.parse("A-3-1")
    end

    test "parses valid location code with lowercase shelf and normalizes to uppercase" do
      assert {:ok, %{shelf_code: "A", bin_code: "3", cell_code: "1"}} =
               LocationParser.parse("a-3-1")
    end

    test "parses location code with multi-character shelf name" do
      assert {:ok, %{shelf_code: "TALL_WORKBENCH", bin_code: "12", cell_code: "5"}} =
               LocationParser.parse("tall_workbench-12-5")
    end

    test "parses location code with multi-digit bin and cell" do
      assert {:ok, %{shelf_code: "B", bin_code: "12", cell_code: "99"}} =
               LocationParser.parse("B-12-99")
    end

    test "parses location code with maximum valid values" do
      max_shelf_len = InventoryLocator.Inventory.Shelf.max_code_length()
      max_bin = InventoryLocator.Inventory.Bin.max_code()
      max_cell = InventoryLocator.Inventory.Cell.max_code()

      expected_shelf = String.duplicate("A", max_shelf_len)

      assert {:ok, result} =
               LocationParser.parse(
                 "#{String.duplicate("a", max_shelf_len)}-#{max_bin}-#{max_cell}"
               )

      assert result.shelf_code == expected_shelf
      assert result.bin_code == "#{max_bin}"
      assert result.cell_code == "#{max_cell}"
    end

    test "returns error for missing parts" do
      assert {:error, :invalid_format} = LocationParser.parse("A-3")
      assert {:error, :invalid_format} = LocationParser.parse("A")
      assert {:error, :invalid_format} = LocationParser.parse("")
    end

    test "returns error for too many parts" do
      assert {:error, :invalid_format} = LocationParser.parse("A-3-1-extra")
    end

    test "returns error for empty components" do
      assert {:error, :invalid_format} = LocationParser.parse("-3-1")
      assert {:error, :invalid_format} = LocationParser.parse("A--1")
      assert {:error, :invalid_format} = LocationParser.parse("A-3-")
    end

    test "returns error for dash in shelf name" do
      assert {:error, :invalid_format} = LocationParser.parse("tall-workbench-3-1")
    end

    test "returns error for special characters in shelf name" do
      assert {:error, :invalid_format} = LocationParser.parse("@shelf-3-1")
      assert {:error, :invalid_format} = LocationParser.parse("shelf!-3-1")
      assert {:error, :invalid_format} = LocationParser.parse("123-3-1")
    end

    test "returns error for shelf name over max length" do
      max_shelf_len = InventoryLocator.Inventory.Shelf.max_code_length()

      assert {:error, :invalid_format} =
               LocationParser.parse("#{String.duplicate("a", max_shelf_len + 1)}-3-1")
    end

    test "returns error for non-integer bin codes" do
      assert {:error, :invalid_format} = LocationParser.parse("A-bin-1")
      assert {:error, :invalid_format} = LocationParser.parse("A-3a-1")
    end

    test "returns error for non-integer cell codes" do
      assert {:error, :invalid_format} = LocationParser.parse("A-3-cell")
      assert {:error, :invalid_format} = LocationParser.parse("A-3-1a")
    end

    test "returns error for bin code out of range" do
      max_bin = InventoryLocator.Inventory.Bin.max_code()
      assert {:error, :invalid_format} = LocationParser.parse("A-#{max_bin + 1}-1")
      assert {:error, :invalid_format} = LocationParser.parse("A--1-1")
    end

    test "returns error for cell code out of range" do
      max_cell = InventoryLocator.Inventory.Cell.max_code()
      assert {:error, :invalid_format} = LocationParser.parse("A-3-#{max_cell + 1}")
      assert {:error, :invalid_format} = LocationParser.parse("A-3--1")
    end

    test "returns error for leading zeros in bin or cell" do
      assert {:error, :invalid_format} = LocationParser.parse("A-03-1")
      assert {:error, :invalid_format} = LocationParser.parse("A-3-01")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_format} = LocationParser.parse(123)
      assert {:error, :invalid_format} = LocationParser.parse(nil)
      assert {:error, :invalid_format} = LocationParser.parse(%{})
    end
  end
end
