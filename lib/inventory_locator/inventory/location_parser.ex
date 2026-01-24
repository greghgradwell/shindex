defmodule InventoryLocator.Inventory.LocationParser do
  @moduledoc false
  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Inventory.Location
  alias InventoryLocator.Inventory.LocationCode
  alias InventoryLocator.Inventory.Shelf
  alias InventoryLocator.Repo

  defmodule Status do
    @moduledoc false
    @type t :: :needs_creation | :exists_empty | :exists_occupied

    def needs_creation, do: :needs_creation
    def exists_empty, do: :exists_empty
    def exists_occupied, do: :exists_occupied
  end

  defmodule Missing do
    @moduledoc false
    @type t :: :shelf | :bin | :location

    def shelf, do: :shelf
    def bin, do: :bin
    def location, do: :location
  end

  @type parsed :: %{
          shelf_code: String.t(),
          bin_code: String.t()
        }

  @type validation_result :: %{
          status: Status.t(),
          missing: [Missing.t()],
          location: Location.t() | nil,
          item_type: ItemType.t() | nil
        }

  @type parse_and_validate_result :: %{
          shelf_code: String.t(),
          bin_code: String.t(),
          status: Status.t(),
          missing: [Missing.t()],
          location: Location.t() | nil,
          item_type: ItemType.t() | nil
        }

  @spec parse(String.t()) :: {:ok, parsed()} | {:error, :invalid_format}
  def parse(location_code) do
    LocationCode.parse(location_code)
  end

  @spec validate(integer(), parsed()) :: {:ok, validation_result()}
  def validate(inventory_id, %{shelf_code: shelf_code, bin_code: bin_code}) do
    entities = fetch_hierarchy(inventory_id, shelf_code, bin_code)
    missing = find_missing_from_hierarchy(entities)

    if Enum.empty?(missing) do
      check_occupancy(entities.location)
    else
      build_needs_creation_result(missing)
    end
  end

  @spec parse_and_validate(integer(), String.t()) ::
          {:ok, parse_and_validate_result()} | {:error, :invalid_format}
  def parse_and_validate(inventory_id, location_code) do
    with {:ok, parsed} <- parse(location_code),
         {:ok, validation} <- validate(inventory_id, parsed) do
      {:ok, Map.merge(parsed, validation)}
    end
  end

  @type hierarchy :: %{
          shelf: Shelf.t() | nil,
          bin: Bin.t() | nil,
          location: Location.t() | nil
        }

  @spec fetch_hierarchy(integer(), String.t(), String.t()) :: hierarchy()
  defp fetch_hierarchy(inventory_id, shelf_code, bin_code) do
    shelf = Repo.get_by(Shelf, code: shelf_code, inventory_id: inventory_id)
    bin = fetch_bin(bin_code, shelf)
    location = fetch_location(bin)

    %{shelf: shelf, bin: bin, location: location}
  end

  @spec fetch_bin(String.t(), Shelf.t() | nil) :: Bin.t() | nil
  defp fetch_bin(_code, nil), do: nil

  defp fetch_bin(code, shelf) do
    Repo.get_by(Bin, code: code, shelf_id: shelf.id)
  end

  @spec fetch_location(Bin.t() | nil) :: Location.t() | nil
  defp fetch_location(nil), do: nil

  defp fetch_location(bin) do
    Repo.get_by(Location, bin_id: bin.id)
  end

  @spec find_missing_from_hierarchy(hierarchy()) :: [Missing.t()]
  defp find_missing_from_hierarchy(%{shelf: shelf, bin: bin, location: location}) do
    [
      {shelf, Missing.shelf()},
      {bin, Missing.bin()},
      {location, Missing.location()}
    ]
    |> Enum.drop_while(fn {entity, _label} -> not is_nil(entity) end)
    |> Enum.map(fn {_entity, label} -> label end)
  end

  @spec build_needs_creation_result([Missing.t()]) :: {:ok, validation_result()}
  defp build_needs_creation_result(missing) do
    {:ok, %{status: Status.needs_creation(), missing: missing, location: nil, item_type: nil}}
  end

  @spec check_occupancy(Location.t()) :: {:ok, validation_result()}
  defp check_occupancy(location) do
    import Ecto.Query

    has_active_items =
      Repo.exists?(
        from i in ItemType,
          where: i.location_id == ^location.id and i.archived == false
      )

    status = if has_active_items, do: Status.exists_occupied(), else: Status.exists_empty()

    {:ok, %{status: status, missing: [], location: location, item_type: nil}}
  end
end
