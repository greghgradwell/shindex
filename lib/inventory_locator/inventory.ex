defmodule InventoryLocator.Inventory do
  @moduledoc false
  import Ecto.Query, warn: false

  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Cell
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Inventory.Location
  alias InventoryLocator.Inventory.LocationParser
  alias InventoryLocator.Inventory.Shelf
  alias InventoryLocator.Repo

  # Shelves

  @spec create_shelf(map()) :: {:ok, Shelf.t()} | {:error, Ecto.Changeset.t()}
  defp create_shelf(attrs) do
    %Shelf{}
    |> Shelf.changeset(attrs)
    |> Repo.insert()
  end

  # Bins

  @spec create_bin(map()) :: {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  defp create_bin(attrs) do
    %Bin{}
    |> Bin.changeset(attrs)
    |> Repo.insert()
  end

  # Cells

  @spec create_cell(map()) :: {:ok, Cell.t()} | {:error, Ecto.Changeset.t()}
  defp create_cell(attrs) do
    %Cell{}
    |> Cell.changeset(attrs)
    |> Repo.insert()
  end

  # Locations

  @spec get_location!(integer()) :: Location.t()
  def get_location!(id), do: Repo.get!(Location, id)

  @spec create_location(map()) :: {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  defp create_location(attrs) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @spec ensure_location_with_code(String.t()) ::
          {:ok, Location.t()}
          | {:ok, Location.t(), integer()}
          | {:error, :invalid_format | Ecto.Changeset.t()}
  def ensure_location_with_code(location_code) do
    with {:ok, parsed} <- LocationParser.parse(location_code),
         {:ok, validation} <- LocationParser.validate(parsed) do
      case validation.status do
        :needs_creation ->
          create_hierarchy(parsed, validation.missing)

        :exists_empty ->
          {:ok, validation.location}

        :exists_occupied ->
          active_item_count = count_active_items_at_location(validation.location.id)
          {:ok, validation.location, active_item_count}
      end
    end
  end

  @spec count_active_items_at_location(integer()) :: integer()
  defp count_active_items_at_location(location_id) do
    Repo.aggregate(
      from(i in ItemType, where: i.location_id == ^location_id and i.archived == false),
      :count
    )
  end

  @spec create_hierarchy(LocationParser.parsed(), [LocationParser.Missing.t()]) ::
          {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  defp create_hierarchy(%{shelf_code: shelf_code, bin_code: bin_code, cell_code: cell_code}, missing) do
    Repo.transaction(fn ->
      shelf = ensure_shelf(shelf_code, missing)
      bin = ensure_bin(bin_code, shelf, missing)
      cell = ensure_cell_with_backfill(cell_code, bin, missing)
      ensure_location(shelf_code, bin_code, cell_code, cell, missing)
    end)
  end

  @spec ensure_shelf(String.t(), [LocationParser.Missing.t()]) :: Shelf.t()
  defp ensure_shelf(shelf_code, missing) do
    if :shelf in missing do
      {:ok, shelf} = create_shelf(%{code: shelf_code})
      shelf
    else
      Repo.get_by!(Shelf, code: shelf_code)
    end
  end

  @spec ensure_bin(String.t(), Shelf.t(), [LocationParser.Missing.t()]) :: Bin.t()
  defp ensure_bin(bin_code, shelf, missing) do
    if :bin in missing do
      {:ok, bin} = create_bin(%{code: bin_code, shelf_id: shelf.id})
      bin
    else
      Repo.get_by!(Bin, code: bin_code, shelf_id: shelf.id)
    end
  end

  @spec ensure_cell_with_backfill(String.t(), Bin.t(), [LocationParser.Missing.t()]) :: Cell.t()
  defp ensure_cell_with_backfill(cell_code, bin, missing) do
    target_cell_num = String.to_integer(cell_code)

    if :cell in missing do
      Enum.each(1..target_cell_num, fn i ->
        code = "#{i}"

        if !Repo.get_by(Cell, code: code, bin_id: bin.id) do
          create_cell(%{code: code, bin_id: bin.id})
        end
      end)
    end

    Repo.get_by!(Cell, code: cell_code, bin_id: bin.id)
  end

  @spec ensure_location(String.t(), String.t(), String.t(), Cell.t(), [
          LocationParser.Missing.t()
        ]) :: Location.t()
  defp ensure_location(shelf_code, bin_code, cell_code, cell, missing) do
    if :location in missing do
      full_code = "#{shelf_code}-#{bin_code}-#{cell_code}"
      {:ok, location} = create_location(%{full_code: full_code, cell_id: cell.id})
      location
    else
      Repo.get_by!(Location, cell_id: cell.id)
    end
  end

  @spec list_shelves_with_hierarchy() :: [Shelf.t()]
  def list_shelves_with_hierarchy do
    Shelf
    |> Repo.all()
    |> Repo.preload(bins: [cells: [location: :item_types]])
  end

  @spec delete_empty_location(integer()) ::
          {:ok, Location.t()} | {:error, :occupied} | {:error, Ecto.Changeset.t()}
  def delete_empty_location(location_id) do
    active_item_count =
      Repo.aggregate(
        from(i in ItemType, where: i.location_id == ^location_id and i.archived == false),
        :count
      )

    if active_item_count > 0 do
      {:error, :occupied}
    else
      Repo.transaction(fn ->
        Repo.update_all(from(i in ItemType, where: i.location_id == ^location_id and i.archived == true),
          set: [location_id: nil]
        )

        location = Location |> Repo.get!(location_id) |> Repo.preload(cell: [bin: :shelf])
        cell = location.cell
        bin = cell.bin
        shelf = bin.shelf

        Repo.delete!(location)

        # Check if cell is now empty (each cell has only one location)
        cell_location_count =
          Repo.aggregate(from(l in Location, where: l.cell_id == ^cell.id), :count)

        if cell_location_count == 0 do
          Repo.delete!(cell)

          # Check if bin has any cells with locations (not just empty orphaned cells)
          bin_occupied_cell_count =
            Repo.aggregate(
              from(c in Cell,
                join: l in assoc(c, :location),
                where: c.bin_id == ^bin.id
              ),
              :count
            )

          if bin_occupied_cell_count == 0 do
            # Delete all orphaned empty cells in the bin
            Repo.delete_all(from(c in Cell, where: c.bin_id == ^bin.id))
            Repo.delete!(bin)

            # Check if shelf has any bins with locations
            shelf_occupied_bin_count =
              Repo.aggregate(
                from(b in Bin,
                  join: c in assoc(b, :cells),
                  join: l in assoc(c, :location),
                  where: b.shelf_id == ^shelf.id
                ),
                :count
              )

            if shelf_occupied_bin_count == 0 do
              # Delete all orphaned empty bins in the shelf
              Repo.delete_all(from(b in Bin, where: b.shelf_id == ^shelf.id))
              Repo.delete!(shelf)
            end
          end
        end

        location
      end)
    end
  end

  @spec count_locations_by_occupancy() :: %{occupied: integer(), empty: integer()}
  def count_locations_by_occupancy do
    Repo.one(
      from(l in Location,
        left_join: i in assoc(l, :item_types),
        where: is_nil(i.archived) or i.archived == false,
        select: %{
          occupied: fragment("COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END)", i.id, l.id),
          empty: fragment("COUNT(DISTINCT ?) - COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END)", l.id, i.id, l.id)
        }
      )
    )
  end

  # ItemTypes

  @spec get_item_type!(integer()) :: ItemType.t()
  def get_item_type!(id), do: Repo.get!(ItemType, id)

  @spec get_item_type_with_location!(integer()) :: ItemType.t()
  def get_item_type_with_location!(id) do
    ItemType
    |> Repo.get!(id)
    |> Repo.preload(location: [cell: [bin: :shelf]])
  end

  @spec create_item_type(map()) :: {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  defp create_item_type(attrs) do
    %ItemType{}
    |> ItemType.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_item_type(ItemType.t(), map()) ::
          {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def update_item_type(%ItemType{} = item, attrs) do
    item
    |> ItemType.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_item_type(ItemType.t()) :: {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def delete_item_type(%ItemType{} = item_type) do
    Repo.delete(item_type)
  end

  @spec archive_item_type(ItemType.t()) :: {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def archive_item_type(%ItemType{} = item) do
    item
    |> ItemType.changeset(%{
      quantity: 0,
      archived: true
    })
    |> Repo.update()
  end

  @spec restore_item_type(ItemType.t(), map()) ::
          {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def restore_item_type(%ItemType{} = item, attrs) do
    item
    |> ItemType.changeset(Map.put(attrs, :archived, false))
    |> Repo.update()
  end

  @spec create_item_with_location(String.t(), String.t(), integer(), String.t()) ::
          {:ok, ItemType.t()} | {:error, :invalid_format | Ecto.Changeset.t()}
  def create_item_with_location(location_code, name, quantity, description) do
    case ensure_location_with_code(location_code) do
      {:ok, location} ->
        create_item_type(%{
          name: name,
          quantity: quantity,
          description: description,
          archived: false,
          location_id: location.id
        })

      {:ok, location, _item_count} ->
        create_item_type(%{
          name: name,
          quantity: quantity,
          description: description,
          archived: false,
          location_id: location.id
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create_item_with_location!(String.t(), String.t(), integer(), String.t()) :: ItemType.t()
  def create_item_with_location!(location_code, name, quantity, description) do
    case create_item_with_location(location_code, name, quantity, description) do
      {:ok, item_type} -> item_type
      {:error, reason} -> raise "Could not create item with location: #{inspect(reason)}"
    end
  end

  @spec search_items(String.t(), keyword()) :: [ItemType.t()]
  def search_items(query, opts) do
    show_archived =
      if Keyword.has_key?(opts, :show_archived) do
        Keyword.fetch!(opts, :show_archived)
      else
        false
      end

    filters =
      if Keyword.has_key?(opts, :filters) do
        Keyword.fetch!(opts, :filters)
      else
        []
      end

    if query == "" and filters == [] do
      []
    else
      ItemType
      |> filter_by_archived(show_archived)
      |> filter_by_missing_fields(filters)
      |> search_by_name(query)
      |> apply_default_ordering(query)
      |> Repo.all()
      |> Repo.preload(location: [cell: [bin: :shelf]])
    end
  end

  @spec filter_by_archived(Ecto.Queryable.t(), boolean()) :: Ecto.Queryable.t()
  defp filter_by_archived(query, false), do: where(query, [i], i.archived == false)
  defp filter_by_archived(query, true), do: query

  @spec filter_by_missing_fields(Ecto.Queryable.t(), [atom()]) :: Ecto.Queryable.t()
  defp filter_by_missing_fields(query, []), do: query

  defp filter_by_missing_fields(query, filters) do
    conditions =
      Enum.map(filters, fn
        :manufacturer -> dynamic([i], is_nil(i.manufacturer))
        :model -> dynamic([i], is_nil(i.model))
        :description -> dynamic([i], is_nil(i.description))
      end)

    combined =
      Enum.reduce(conditions, fn condition, acc ->
        dynamic([], ^acc or ^condition)
      end)

    query
    |> where(^combined)
    |> where([i], i.archived == false)
  end

  @spec search_by_name(Ecto.Queryable.t(), String.t()) :: Ecto.Queryable.t()
  defp search_by_name(query, ""), do: query

  defp search_by_name(query, search_query) do
    query
    |> where([i], fragment("similarity(?, ?) > 0.3", i.name, ^search_query))
    |> order_by([i],
      desc: fragment("similarity(?, ?)", i.name, ^search_query),
      asc: i.archived,
      asc: i.name
    )
  end

  @spec apply_default_ordering(Ecto.Queryable.t(), String.t()) :: Ecto.Queryable.t()
  defp apply_default_ordering(query, search_query) when search_query != "" do
    query
  end

  defp apply_default_ordering(query, _empty_query) do
    order_by(query, [i], asc: i.archived, asc: i.name)
  end
end
