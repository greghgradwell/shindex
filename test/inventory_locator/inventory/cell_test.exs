defmodule InventoryLocator.Inventory.CellTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory.Cell
  alias InventoryLocator.InventoryCodeTestHelper

  describe "valid_code?/1" do
    test "validates integer codes according to module constraints" do
      InventoryCodeTestHelper.test_integer_code_validation(Cell)
    end
  end
end
