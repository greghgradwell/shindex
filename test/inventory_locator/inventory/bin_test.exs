defmodule InventoryLocator.Inventory.BinTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.InventoryCodeTestHelper

  describe "valid_code?/1" do
    test "validates integer codes according to module constraints" do
      InventoryCodeTestHelper.test_integer_code_validation(Bin)
    end
  end
end
