defmodule InventoryLocator.Inventory.IntegerCodeValidator do
  @spec valid_code?(any(), integer(), integer()) :: boolean()
  def valid_code?(code, min, max) when is_binary(code) do
    case Integer.parse(code) do
      {n, ""} when n >= min and n <= max ->
        Integer.to_string(n) == code

      _ ->
        false
    end
  end

  def valid_code?(_, _, _), do: false

  @spec error_message(integer(), integer()) :: String.t()
  def error_message(min, max) do
    "must be an integer between #{min} and #{max}"
  end
end
