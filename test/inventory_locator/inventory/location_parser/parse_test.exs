defmodule InventoryLocator.Inventory.LocationParser.ParseTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.LocationParser
  alias InventoryLocator.Inventory.Shelf

  describe "parse/1" do
    test "parses valid location code with uppercase shelf" do
      assert {:ok, %{shelf_code: "A", bin_code: "3"}} =
               LocationParser.parse("A-3")
    end

    test "parses valid location code with lowercase shelf and normalizes to uppercase" do
      assert {:ok, %{shelf_code: "A", bin_code: "3"}} =
               LocationParser.parse("a-3")
    end

    test "parses location code with multi-character shelf name" do
      assert {:ok, %{shelf_code: "TALL_WORKBENCH", bin_code: "12"}} =
               LocationParser.parse("tall_workbench-12")
    end

    test "parses location code with multi-digit bin" do
      assert {:ok, %{shelf_code: "B", bin_code: "12"}} =
               LocationParser.parse("B-12")
    end

    test "parses location code with maximum valid values" do
      max_shelf_len = Shelf.max_code_length()
      max_bin = Bin.max_code()

      expected_shelf = String.duplicate("A", max_shelf_len)

      assert {:ok, result} =
               LocationParser.parse("#{String.duplicate("a", max_shelf_len)}-#{max_bin}")

      assert result.shelf_code == expected_shelf
      assert result.bin_code == "#{max_bin}"
    end

    test "returns error for missing parts" do
      assert {:error, :invalid_format} = LocationParser.parse("A")
      assert {:error, :invalid_format} = LocationParser.parse("")
    end

    test "returns error for too many parts" do
      assert {:error, :invalid_format} = LocationParser.parse("A-3-1-extra")
    end

    test "returns error for empty components" do
      assert {:error, :invalid_format} = LocationParser.parse("-3")
      assert {:error, :invalid_format} = LocationParser.parse("A-")
    end

    test "returns error for dash in shelf name" do
      assert {:error, :invalid_format} = LocationParser.parse("tall-workbench-3")
    end

    test "returns error for special characters in shelf name" do
      assert {:error, :invalid_format} = LocationParser.parse("@shelf-3")
      assert {:error, :invalid_format} = LocationParser.parse("shelf!-3")
      assert {:error, :invalid_format} = LocationParser.parse("123-3")
    end

    test "returns error for shelf name over max length" do
      max_shelf_len = Shelf.max_code_length()

      assert {:error, :invalid_format} =
               LocationParser.parse("#{String.duplicate("a", max_shelf_len + 1)}-3")
    end

    test "returns error for non-integer bin codes" do
      assert {:error, :invalid_format} = LocationParser.parse("A-bin")
      assert {:error, :invalid_format} = LocationParser.parse("A-3a")
    end

    test "returns error for bin code out of range" do
      max_bin = Bin.max_code()
      assert {:error, :invalid_format} = LocationParser.parse("A-#{max_bin + 1}")
      assert {:error, :invalid_format} = LocationParser.parse("A--1")
    end

    test "returns error for leading zeros in bin" do
      assert {:error, :invalid_format} = LocationParser.parse("A-03")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_format} = LocationParser.parse(123)
      assert {:error, :invalid_format} = LocationParser.parse(nil)
      assert {:error, :invalid_format} = LocationParser.parse(%{})
    end
  end
end
