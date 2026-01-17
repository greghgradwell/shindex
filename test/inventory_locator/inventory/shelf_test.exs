defmodule InventoryLocator.Inventory.ShelfTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory.Shelf

  describe "valid_code?/1" do
    test "returns true for valid lowercase letter codes" do
      assert Shelf.valid_code?("a")
      assert Shelf.valid_code?("abc")
      assert Shelf.valid_code?("workbench")
    end

    test "returns true for valid uppercase letter codes" do
      assert Shelf.valid_code?("A")
      assert Shelf.valid_code?("ABC")
      assert Shelf.valid_code?("WORKBENCH")
    end

    test "returns true for codes with underscores in middle" do
      assert Shelf.valid_code?("tall_workbench")
      assert Shelf.valid_code?("shelf_a")
      assert Shelf.valid_code?("a_b_c")
    end

    test "returns false for codes with leading underscores" do
      refute Shelf.valid_code?("_shelf")
      refute Shelf.valid_code?("_a")
    end

    test "returns false for codes with trailing underscores" do
      refute Shelf.valid_code?("shelf_")
      refute Shelf.valid_code?("a_")
    end

    test "returns true for codes up to max length" do
      assert Shelf.valid_code?(String.duplicate("a", Shelf.max_code_length()))
    end

    test "returns false for codes over max length" do
      refute Shelf.valid_code?(String.duplicate("a", Shelf.max_code_length() + 1))
    end

    test "returns false for empty string" do
      refute Shelf.valid_code?("")
    end

    test "returns false for codes with dashes" do
      refute Shelf.valid_code?("tall-workbench")
      refute Shelf.valid_code?("a-b")
    end

    test "returns true for codes with numbers" do
      assert Shelf.valid_code?("shelf1")
      assert Shelf.valid_code?("a2b")
      assert Shelf.valid_code?("SHELF_2")
      assert Shelf.valid_code?("A1")
    end

    test "returns false for codes starting with numbers" do
      refute Shelf.valid_code?("1shelf")
      refute Shelf.valid_code?("2")
      refute Shelf.valid_code?("123")
    end

    test "returns false for codes with special characters" do
      refute Shelf.valid_code?("shelf!")
      refute Shelf.valid_code?("@shelf")
      refute Shelf.valid_code?("shelf space")
    end

    test "returns false for non-string input" do
      refute Shelf.valid_code?(123)
      refute Shelf.valid_code?(nil)
      refute Shelf.valid_code?(%{})
    end
  end
end
