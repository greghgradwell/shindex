defmodule InventoryLocator.Inventory.LocationCode do
  @moduledoc false
  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Shelf

  require Logger

  @type parsed :: %{
          shelf_code: String.t(),
          bin_code: String.t()
        }

  @spec parse(String.t()) :: {:ok, parsed()} | {:error, :invalid_format}
  def parse(code) when is_binary(code) do
    case String.split(code, "-") do
      [shelf, bin] ->
        if valid_components?(shelf, bin) do
          {:ok,
           %{
             shelf_code: String.upcase(shelf),
             bin_code: bin
           }}
        else
          {:error, :invalid_format}
        end

      parts ->
        Logger.debug("Invalid location code format, expected 2 parts: #{inspect(parts)}")
        {:error, :invalid_format}
    end
  end

  def parse(_), do: {:error, :invalid_format}

  @spec valid?(String.t()) :: boolean()
  def valid?(code) do
    case parse(code) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @spec valid_components?(String.t(), String.t()) :: boolean()
  defp valid_components?(shelf, bin) do
    Shelf.valid_code?(shelf) && Bin.valid_code?(bin)
  end

  @spec shelf_code!(String.t()) :: String.t()
  def shelf_code!(location_code) do
    case parse(location_code) do
      {:ok, %{shelf_code: code}} -> code
      {:error, :invalid_format} -> raise ArgumentError, "Invalid location code: #{location_code}"
    end
  end

  @spec bin_code!(String.t()) :: String.t()
  def bin_code!(location_code) do
    case parse(location_code) do
      {:ok, %{bin_code: code}} -> code
      {:error, :invalid_format} -> raise ArgumentError, "Invalid location code: #{location_code}"
    end
  end
end
