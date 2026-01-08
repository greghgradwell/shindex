defmodule InventoryLocator.Inventory.LocationCodeTest do
  use ExUnit.Case, async: true

  alias InventoryLocator.Inventory.LocationCode

  describe "parse/1" do
    test "parses valid location code with uppercase shelf" do
      assert {:ok, %{shelf_code: "A", bin_code: "1", cell_code: "1"}} =
               LocationCode.parse("A-1-1")
    end

    test "parses valid location code with lowercase shelf and uppercases it" do
      assert {:ok, %{shelf_code: "A", bin_code: "1", cell_code: "1"}} =
               LocationCode.parse("a-1-1")
    end

    test "parses valid location code with multi-digit bin and cell" do
      assert {:ok, %{shelf_code: "B", bin_code: "12", cell_code: "99"}} =
               LocationCode.parse("B-12-99")
    end

    test "returns error for invalid format without dashes" do
      assert {:error, :invalid_format} = LocationCode.parse("A10")
    end

    test "returns error for invalid format with too few components" do
      assert {:error, :invalid_format} = LocationCode.parse("A-1")
    end

    test "returns error for invalid format with too many components" do
      assert {:error, :invalid_format} = LocationCode.parse("A-1-1-extra")
    end

    test "returns error for invalid shelf code" do
      assert {:error, :invalid_format} = LocationCode.parse("1-1-0")
      assert {:error, :invalid_format} = LocationCode.parse("-1-0")
      assert {:error, :invalid_format} = LocationCode.parse("ABC_123-1-0")
    end

    test "returns error for invalid bin code" do
      assert {:error, :invalid_format} = LocationCode.parse("A-abc-0")
      assert {:error, :invalid_format} = LocationCode.parse("A--0")
    end

    test "returns error for invalid cell code" do
      assert {:error, :invalid_format} = LocationCode.parse("A-1-abc")
      assert {:error, :invalid_format} = LocationCode.parse("A-1-")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_format} = LocationCode.parse("")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_format} = LocationCode.parse(nil)
      assert {:error, :invalid_format} = LocationCode.parse(123)
      assert {:error, :invalid_format} = LocationCode.parse(:atom)
    end
  end

  describe "valid?/1" do
    test "returns true for valid location codes" do
      assert LocationCode.valid?("A-1-1")
      assert LocationCode.valid?("a-1-1")
      assert LocationCode.valid?("Z-99-99")
      assert LocationCode.valid?("AB-5-10")
    end

    test "returns false for invalid location codes" do
      refute LocationCode.valid?("A10")
      refute LocationCode.valid?("A-1")
      refute LocationCode.valid?("1-1-0")
      refute LocationCode.valid?("A-abc-0")
      refute LocationCode.valid?("A-1-xyz")
      refute LocationCode.valid?("")
      refute LocationCode.valid?(nil)
      refute LocationCode.valid?(123)
    end
  end

  describe "shelf_code!/1" do
    test "extracts shelf code from valid location code" do
      assert LocationCode.shelf_code!("A-1-1") == "A"
      assert LocationCode.shelf_code!("B-12-99") == "B"
    end

    test "uppercases lowercase shelf code" do
      assert LocationCode.shelf_code!("a-1-1") == "A"
    end

    test "raises ArgumentError for invalid location code" do
      assert_raise ArgumentError, ~r/Invalid location code/, fn ->
        LocationCode.shelf_code!("invalid")
      end
    end
  end

  describe "bin_code!/1" do
    test "extracts bin code from valid location code" do
      assert LocationCode.bin_code!("A-1-1") == "1"
      assert LocationCode.bin_code!("B-12-99") == "12"
    end

    test "raises ArgumentError for invalid location code" do
      assert_raise ArgumentError, ~r/Invalid location code/, fn ->
        LocationCode.bin_code!("A-1")
      end
    end
  end

  describe "cell_code!/1" do
    test "extracts cell code from valid location code" do
      assert LocationCode.cell_code!("A-1-1") == "1"
      assert LocationCode.cell_code!("B-12-99") == "99"
    end

    test "raises ArgumentError for invalid location code" do
      assert_raise ArgumentError, ~r/Invalid location code/, fn ->
        LocationCode.cell_code!("A-abc-0")
      end
    end
  end
end
