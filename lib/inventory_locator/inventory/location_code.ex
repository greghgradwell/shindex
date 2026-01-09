defmodule InventoryLocator.Inventory.LocationCode do
  @moduledoc false
  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Cell
  alias InventoryLocator.Inventory.Shelf

  @type parsed :: %{
          shelf_code: String.t(),
          bin_code: String.t(),
          cell_code: String.t()
        }

  @spec parse(String.t()) :: {:ok, parsed()} | {:error, :invalid_format}
  def parse(code) when is_binary(code) do
    case String.split(code, "-") do
      [shelf, bin, cell] ->
        if valid_components?(shelf, bin, cell) do
          {:ok,
           %{
             shelf_code: String.upcase(shelf),
             bin_code: bin,
             cell_code: cell
           }}
        else
          {:error, :invalid_format}
        end

      _ ->
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

  @spec valid_components?(String.t(), String.t(), String.t()) :: boolean()
  defp valid_components?(shelf, bin, cell) do
    Shelf.valid_code?(shelf) && Bin.valid_code?(bin) && Cell.valid_code?(cell)
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

  @spec cell_code!(String.t()) :: String.t()
  def cell_code!(location_code) do
    case parse(location_code) do
      {:ok, %{cell_code: code}} -> code
      {:error, :invalid_format} -> raise ArgumentError, "Invalid location code: #{location_code}"
    end
  end
end
