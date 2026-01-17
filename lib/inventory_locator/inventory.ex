defmodule InventoryLocator.Inventory do
  @moduledoc false
  import Ecto.Query, warn: false

  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Cell
  alias InventoryLocator.Inventory.ItemInstallation
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

  @spec get_shelf!(integer()) :: Shelf.t()
  def get_shelf!(id), do: Repo.get!(Shelf, id)

  @spec create_shelf_with_bins(map(), pos_integer()) ::
          {:ok, Shelf.t()} | {:error, Ecto.Changeset.t()}
  def create_shelf_with_bins(shelf_attrs, bin_count) when bin_count >= 1 do
    Repo.transaction(fn ->
      case create_shelf(shelf_attrs) do
        {:ok, shelf} ->
          Enum.each(1..bin_count, fn bin_num ->
            create_bin_with_cell_1(shelf, "#{bin_num}")
          end)

          Repo.preload(shelf, bins: :cells)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @spec add_bin_to_shelf(Shelf.t()) :: {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  def add_bin_to_shelf(%Shelf{} = shelf) do
    next_bin_code = get_next_bin_code(shelf.id)

    Repo.transaction(fn ->
      case create_bin_with_cell_1(shelf, next_bin_code) do
        {:ok, bin} -> bin
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @spec get_next_bin_code(integer()) :: String.t()
  defp get_next_bin_code(shelf_id) do
    max_code =
      Repo.one(
        from(b in Bin,
          where: b.shelf_id == ^shelf_id,
          select: max(fragment("CAST(? AS INTEGER)", b.code))
        )
      ) || 0

    "#{max_code + 1}"
  end

  @spec create_bin_with_cell_1(Shelf.t(), String.t()) ::
          {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  defp create_bin_with_cell_1(shelf, bin_code) do
    with {:ok, bin} <- create_bin(%{code: bin_code, shelf_id: shelf.id}),
         {:ok, cell} <- create_cell(%{code: "1", bin_id: bin.id}),
         full_code = "#{shelf.code}-#{bin_code}-1",
         {:ok, _location} <- create_location(%{full_code: full_code, cell_id: cell.id}) do
      {:ok, Repo.preload(bin, :cells)}
    end
  end

  @spec rename_shelf(Shelf.t(), String.t()) ::
          {:ok, Shelf.t()} | {:error, :invalid_code | :code_exists | Ecto.Changeset.t()}
  def rename_shelf(%Shelf{} = shelf, new_code) do
    new_code = String.upcase(new_code)

    cond do
      not Shelf.valid_code?(new_code) ->
        {:error, :invalid_code}

      shelf.code == new_code ->
        {:ok, shelf}

      Repo.exists?(from(s in Shelf, where: s.code == ^new_code)) ->
        {:error, :code_exists}

      true ->
        do_rename_shelf(shelf, new_code)
    end
  end

  @spec do_rename_shelf(Shelf.t(), String.t()) ::
          {:ok, Shelf.t()} | {:error, Ecto.Changeset.t()}
  defp do_rename_shelf(shelf, new_code) do
    old_code = shelf.code
    old_prefix_len = String.length(old_code) + 1

    Repo.transaction(fn ->
      # Update all Location.full_code strings that start with the old shelf code
      # Cast position to integer explicitly for Postgrex type inference
      Repo.update_all(
        from(l in Location,
          where: like(l.full_code, ^"#{old_code}-%"),
          update: [set: [full_code: fragment("? || substring(full_code, ?::int)", ^new_code, ^old_prefix_len)]]
        ),
        []
      )

      # Update the shelf code
      case Repo.update(Shelf.changeset(shelf, %{code: new_code})) do
        {:ok, updated_shelf} -> updated_shelf
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @spec count_locations_for_shelf(Shelf.t()) :: non_neg_integer()
  def count_locations_for_shelf(%Shelf{} = shelf) do
    Repo.aggregate(
      from(l in Location, where: like(l.full_code, ^"#{shelf.code}-%")),
      :count
    )
  end

  @spec delete_empty_shelf(Shelf.t()) ::
          {:ok, Shelf.t()} | {:error, :has_items}
  def delete_empty_shelf(%Shelf{} = shelf) do
    active_item_count =
      Repo.aggregate(
        from(i in ItemType,
          join: l in Location,
          on: i.location_id == l.id,
          where: like(l.full_code, ^"#{shelf.code}-%") and i.archived == false
        ),
        :count
      )

    if active_item_count > 0 do
      {:error, :has_items}
    else
      Repo.transaction(fn ->
        location_ids = Repo.all(from(l in Location, where: like(l.full_code, ^"#{shelf.code}-%"), select: l.id))

        Repo.update_all(
          from(i in ItemType, where: i.location_id in ^location_ids and i.archived == true),
          set: [location_id: nil]
        )

        Repo.delete_all(from(l in Location, where: l.id in ^location_ids))

        bin_ids = Repo.all(from(b in Bin, where: b.shelf_id == ^shelf.id, select: b.id))
        Repo.delete_all(from(c in Cell, where: c.bin_id in ^bin_ids))
        Repo.delete_all(from(b in Bin, where: b.id in ^bin_ids))

        Repo.delete!(shelf)
      end)
    end
  end

  # Bins

  @spec create_bin(map()) :: {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  defp create_bin(attrs) do
    %Bin{}
    |> Bin.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_bin!(integer()) :: Bin.t()
  def get_bin!(id), do: Repo.get!(Bin, id)

  # Cells

  @spec create_cell(map()) :: {:ok, Cell.t()} | {:error, Ecto.Changeset.t()}
  defp create_cell(attrs) do
    %Cell{}
    |> Cell.changeset(attrs)
    |> Repo.insert()
  end

  @spec add_cell_to_bin(Bin.t()) :: {:ok, Cell.t()} | {:error, Ecto.Changeset.t()}
  def add_cell_to_bin(%Bin{} = bin) do
    bin = Repo.preload(bin, :shelf)
    next_cell_code = get_next_cell_code(bin.id)
    full_code = "#{bin.shelf.code}-#{bin.code}-#{next_cell_code}"

    Repo.transaction(fn ->
      with {:ok, cell} <- create_cell(%{code: next_cell_code, bin_id: bin.id}),
           {:ok, _location} <- create_location(%{full_code: full_code, cell_id: cell.id}) do
        Repo.preload(cell, :location)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @spec get_next_cell_code(integer()) :: String.t()
  defp get_next_cell_code(bin_id) do
    max_code =
      Repo.one(
        from(c in Cell,
          where: c.bin_id == ^bin_id,
          select: max(fragment("CAST(? AS INTEGER)", c.code))
        )
      ) || 0

    "#{max_code + 1}"
  end

  @spec create_cell_with_location(Bin.t(), String.t()) ::
          {:ok, Cell.t()} | {:error, Ecto.Changeset.t()}
  def create_cell_with_location(%Bin{} = bin, cell_code) do
    bin = Repo.preload(bin, :shelf)
    full_code = "#{bin.shelf.code}-#{bin.code}-#{cell_code}"

    Repo.transaction(fn ->
      with {:ok, cell} <- create_cell(%{code: cell_code, bin_id: bin.id}),
           {:ok, location} <- create_location(%{full_code: full_code, cell_id: cell.id}) do
        %{cell | location: location}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Locations

  @spec get_location!(integer()) :: Location.t()
  def get_location!(id), do: Repo.get!(Location, id)

  @spec list_location_codes() :: [String.t()]
  def list_location_codes do
    Repo.all(from(l in Location, select: l.full_code, order_by: l.full_code))
  end

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

  @type validate_location_result ::
          {:ok, :exists, Location.t()}
          | {:ok, :exists_occupied, Location.t(), non_neg_integer()}
          | {:ok, :needs_cell, Bin.t(), String.t()}
          | {:error, :invalid_format}
          | {:error, :shelf_not_found, String.t()}
          | {:error, :bin_not_found, String.t(), String.t()}

  @spec validate_location_code(String.t()) :: validate_location_result()
  def validate_location_code(location_code) do
    case LocationParser.parse(location_code) do
      {:error, :invalid_format} ->
        {:error, :invalid_format}

      {:ok, %{shelf_code: shelf_code, bin_code: bin_code, cell_code: cell_code}} ->
        validate_location_hierarchy(shelf_code, bin_code, cell_code)
    end
  end

  @spec validate_location_hierarchy(String.t(), String.t(), String.t()) ::
          validate_location_result()
  defp validate_location_hierarchy(shelf_code, bin_code, cell_code) do
    shelf = Repo.get_by(Shelf, code: shelf_code)

    if is_nil(shelf) do
      {:error, :shelf_not_found, shelf_code}
    else
      validate_bin_and_cell(shelf, bin_code, cell_code)
    end
  end

  @spec validate_bin_and_cell(Shelf.t(), String.t(), String.t()) :: validate_location_result()
  defp validate_bin_and_cell(shelf, bin_code, cell_code) do
    bin = Repo.get_by(Bin, code: bin_code, shelf_id: shelf.id)

    if is_nil(bin) do
      {:error, :bin_not_found, shelf.code, bin_code}
    else
      validate_cell_and_location(bin, cell_code)
    end
  end

  @spec validate_cell_and_location(Bin.t(), String.t()) :: validate_location_result()
  defp validate_cell_and_location(bin, cell_code) do
    cell = Repo.get_by(Cell, code: cell_code, bin_id: bin.id)

    if is_nil(cell) do
      {:ok, :needs_cell, bin, cell_code}
    else
      location = Repo.get_by!(Location, cell_id: cell.id)
      active_count = count_active_items_at_location(location.id)

      if active_count > 0 do
        {:ok, :exists_occupied, location, active_count}
      else
        {:ok, :exists, location}
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
    bins_query = from(b in Bin, order_by: b.code)
    cells_query = from(c in Cell, order_by: [desc: c.code])

    shelves_query =
      from(s in Shelf,
        order_by: [
          asc: fragment("length(?) - length(replace(?, '_', ''))", s.code, s.code),
          asc: s.code
        ]
      )

    shelves_query
    |> Repo.all()
    |> Repo.preload(bins: {bins_query, cells: {cells_query, location: :item_types}})
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
  def create_item_type(attrs) do
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

  @spec list_incomplete_items([atom()]) :: [ItemType.t()]
  def list_incomplete_items(missing_fields) when is_list(missing_fields) do
    ItemType
    |> filter_by_archived(false)
    |> filter_by_missing_fields(missing_fields)
    |> order_by([i], asc: i.name)
    |> Repo.all()
    |> Repo.preload(location: [cell: [bin: :shelf]])
  end

  @spec get_next_incomplete_item(integer(), [atom()]) :: ItemType.t() | nil
  def get_next_incomplete_item(current_id, missing_fields) when is_list(missing_fields) do
    current_item = Repo.get(ItemType, current_id)

    if is_nil(current_item) do
      nil
    else
      ItemType
      |> filter_by_archived(false)
      |> filter_by_missing_fields(missing_fields)
      |> where([i], i.name > ^current_item.name or (i.name == ^current_item.name and i.id > ^current_id))
      |> order_by([i], asc: i.name, asc: i.id)
      |> limit(1)
      |> Repo.one()
      |> maybe_preload_location()
    end
  end

  @spec maybe_preload_location(ItemType.t() | nil) :: ItemType.t() | nil
  defp maybe_preload_location(nil), do: nil
  defp maybe_preload_location(item), do: Repo.preload(item, location: [cell: [bin: :shelf]])

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

  @spec list_all_items(keyword()) :: [ItemType.t()]
  def list_all_items(opts) do
    show_archived = Keyword.get(opts, :show_archived, false)
    sort_by = Keyword.get(opts, :sort_by, :name)
    sort_order = Keyword.get(opts, :sort_order, :asc)

    ItemType
    |> filter_by_archived(show_archived)
    |> apply_sort(sort_by, sort_order)
    |> Repo.all()
    |> Repo.preload(location: [cell: [bin: :shelf]])
  end

  @spec filter_by_archived(Ecto.Queryable.t(), boolean()) :: Ecto.Queryable.t()
  defp filter_by_archived(query, false), do: where(query, [i], i.archived == false)
  defp filter_by_archived(query, true), do: query

  @spec apply_sort(Ecto.Queryable.t(), atom(), :asc | :desc) :: Ecto.Queryable.t()
  defp apply_sort(query, :name, order) do
    order_by(query, [i], [{^order, i.name}])
  end

  defp apply_sort(query, :manufacturer, order) do
    order_by(query, [i], [
      {^order, fragment("COALESCE(?, '')", i.manufacturer)},
      {:asc, i.name}
    ])
  end

  defp apply_sort(query, :location, order) do
    query
    |> join(:left, [i], l in assoc(i, :location))
    |> order_by([i, l], [{^order, fragment("COALESCE(?, '')", l.full_code)}, {:asc, i.name}])
  end

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

  # Installations

  @spec list_installations_for_item(ItemType.t()) :: [ItemInstallation.t()]
  def list_installations_for_item(%ItemType{} = item) do
    Repo.all(
      from(i in ItemInstallation,
        where: i.item_type_id == ^item.id,
        order_by: i.project_name
      )
    )
  end

  @spec list_project_names() :: [String.t()]
  def list_project_names do
    Repo.all(
      from(i in ItemInstallation,
        distinct: i.project_name,
        select: i.project_name,
        order_by: i.project_name
      )
    )
  end

  @spec list_items_in_project(String.t()) :: [{ItemInstallation.t(), ItemType.t()}]
  def list_items_in_project(project_name) do
    from(i in ItemInstallation,
      join: item in assoc(i, :item_type),
      where: i.project_name == ^String.upcase(project_name),
      preload: [item_type: {item, location: [cell: [bin: :shelf]]}],
      order_by: item.name
    )
    |> Repo.all()
    |> Enum.map(fn installation -> {installation, installation.item_type} end)
  end

  @spec install_item(ItemType.t(), String.t(), pos_integer()) ::
          {:ok, ItemInstallation.t(), ItemType.t()}
          | {:error, :insufficient_quantity | :archived | Ecto.Changeset.t()}
  def install_item(%ItemType{} = item, project_name, quantity)
      when is_binary(project_name) and project_name != "" and is_integer(quantity) and quantity > 0 do
    project_name = String.upcase(project_name)

    fn ->
      fresh_item = Repo.get!(ItemType, item.id)

      cond do
        fresh_item.archived ->
          Repo.rollback(:archived)

        quantity > fresh_item.quantity ->
          Repo.rollback(:insufficient_quantity)

        true ->
          new_item_quantity = fresh_item.quantity - quantity

          updated_item =
            if new_item_quantity == 0 do
              {:ok, archived} = archive_item_type(fresh_item)
              archived
            else
              {:ok, updated} = update_item_type(fresh_item, %{quantity: new_item_quantity})
              updated
            end

          installation = upsert_installation(fresh_item.id, project_name, quantity)
          {installation, updated_item}
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {installation, updated_item}} -> {:ok, installation, updated_item}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec upsert_installation(integer(), String.t(), pos_integer()) :: ItemInstallation.t()
  defp upsert_installation(item_type_id, project_name, quantity) do
    {:ok, installation} =
      %ItemInstallation{}
      |> ItemInstallation.changeset(%{
        item_type_id: item_type_id,
        project_name: project_name,
        quantity: quantity
      })
      |> Repo.insert(
        on_conflict: [inc: [quantity: quantity]],
        conflict_target: [:item_type_id, :project_name],
        returning: true
      )

    installation
  end

  @spec uninstall_item(ItemInstallation.t(), pos_integer()) ::
          {:ok, :returned_to_stock, ItemType.t()}
          | {:ok, :needs_restore, pos_integer()}
          | {:error, Ecto.Changeset.t()}
  def uninstall_item(%ItemInstallation{} = installation, quantity) when is_integer(quantity) and quantity > 0 do
    fn ->
      fresh_installation = ItemInstallation |> Repo.get!(installation.id) |> Repo.preload(:item_type)
      item = fresh_installation.item_type
      uninstall_quantity = min(quantity, fresh_installation.quantity)
      remaining = fresh_installation.quantity - uninstall_quantity

      if remaining <= 0 do
        Repo.delete!(fresh_installation)
      else
        {:ok, _} =
          fresh_installation
          |> ItemInstallation.changeset(%{quantity: remaining})
          |> Repo.update()
      end

      if item.archived do
        {:needs_restore, uninstall_quantity}
      else
        {:ok, updated_item} = update_item_type(item, %{quantity: item.quantity + uninstall_quantity})
        {:returned_to_stock, updated_item}
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {:returned_to_stock, updated_item}} -> {:ok, :returned_to_stock, updated_item}
      {:ok, {:needs_restore, qty}} -> {:ok, :needs_restore, qty}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec project_has_archived_items?(String.t()) :: boolean()
  def project_has_archived_items?(project_name) do
    Repo.exists?(
      from(i in ItemInstallation,
        join: item in assoc(i, :item_type),
        where: i.project_name == ^String.upcase(project_name),
        where: item.archived == true
      )
    )
  end

  @spec list_archived_items_in_project(String.t()) :: [ItemInstallation.t()]
  def list_archived_items_in_project(project_name) do
    Repo.all(
      from(i in ItemInstallation,
        join: item in assoc(i, :item_type),
        where: i.project_name == ^String.upcase(project_name),
        where: item.archived == true,
        preload: [item_type: item],
        order_by: item.name
      )
    )
  end

  @spec uninstall_all_from_project(String.t()) ::
          {:ok, non_neg_integer()} | {:error, :has_archived_items | term()}
  def uninstall_all_from_project(project_name) do
    if project_has_archived_items?(project_name) do
      {:error, :has_archived_items}
    else
      installations =
        Repo.all(
          from(i in ItemInstallation,
            where: i.project_name == ^String.upcase(project_name),
            preload: :item_type
          )
        )

      Repo.transaction(fn ->
        Enum.reduce(installations, 0, fn installation, count ->
          item = installation.item_type
          {:ok, _} = update_item_type(item, %{quantity: item.quantity + installation.quantity})
          Repo.delete!(installation)
          count + installation.quantity
        end)
      end)
    end
  end

  @spec list_all_projects_with_items() :: [{String.t(), [ItemInstallation.t()]}]
  def list_all_projects_with_items do
    from(i in ItemInstallation,
      join: item in assoc(i, :item_type),
      preload: [item_type: {item, location: [cell: [bin: :shelf]]}],
      order_by: [i.project_name, item.name]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.project_name)
    |> Enum.sort_by(fn {project_name, _} -> project_name end)
  end
end
