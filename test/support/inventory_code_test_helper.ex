defmodule InventoryLocator.InventoryCodeTestHelper do
  @moduledoc false
  import ExUnit.Assertions

  def test_integer_code_validation(module) do
    min_value = module.min_code()
    max_value = module.max_code()

    assert module.valid_code?("#{min_value}")
    assert module.valid_code?("#{max_value}")
    assert module.valid_code?("#{div(min_value + max_value, 2)}")

    refute module.valid_code?("#{max_value + 1}")
    refute module.valid_code?("#{min_value - 1}")
    refute module.valid_code?("-1")
    refute module.valid_code?("1.5")
    refute module.valid_code?("01")
    refute module.valid_code?("abc")
    refute module.valid_code?("")
    refute module.valid_code?(" 1")
    refute module.valid_code?("1 ")
    refute module.valid_code?(123)
    refute module.valid_code?(nil)
    refute module.valid_code?(%{})
  end
end
