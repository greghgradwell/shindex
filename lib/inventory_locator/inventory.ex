defmodule InventoryLocator.Inventory do
  @moduledoc false
  import Ecto.Query, warn: false

  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Inv
  alias InventoryLocator.Inventory.InventoryMember
  alias InventoryLocator.Inventory.InventoryShareCode
  alias InventoryLocator.Inventory.ItemInstallation
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Inventory.Location
  alias InventoryLocator.Inventory.LocationParser
  alias InventoryLocator.Inventory.Shelf
  alias InventoryLocator.Marketplace.Listing
  alias InventoryLocator.Repo

  @similarity_threshold 0.3

  # Inventories

  @spec list_accessible_inventories(integer()) :: [Inv.t()]
  def list_accessible_inventories(user_id) do
    Repo.all(
      from(i in Inv,
        left_join: m in InventoryMember,
        on: m.inventory_id == i.id and m.user_id == ^user_id,
        where: i.user_id == ^user_id or not is_nil(m.id),
        order_by: i.name
      )
    )
  end

  @spec get_inventory!(integer()) :: Inv.t()
  def get_inventory!(id), do: Repo.get!(Inv, id)

  @spec get_inventory(integer() | nil) :: Inv.t() | nil
  def get_inventory(nil), do: nil
  def get_inventory(id), do: Repo.get(Inv, id)

  @spec get_first_inventory!(integer()) :: Inv.t()
  def get_first_inventory!(user_id) do
    Repo.one!(from(i in Inv, where: i.user_id == ^user_id, order_by: i.name, limit: 1))
  end

  @spec create_inventory(map()) :: {:ok, Inv.t()} | {:error, Ecto.Changeset.t()}
  def create_inventory(attrs) do
    %Inv{}
    |> Inv.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_inventory(Inv.t(), map()) :: {:ok, Inv.t()} | {:error, Ecto.Changeset.t()}
  def update_inventory(%Inv{} = inv, attrs) do
    inv
    |> Inv.changeset(attrs)
    |> Repo.update()
  end

  @spec list_accessible_inventories_with_counts(integer()) :: [{Inv.t(), non_neg_integer(), non_neg_integer()}]
  def list_accessible_inventories_with_counts(user_id) do
    Repo.all(
      from(i in Inv,
        left_join: m in InventoryMember,
        on: m.inventory_id == i.id and m.user_id == ^user_id,
        left_join: s in Shelf,
        on: s.inventory_id == i.id,
        left_join: it in ItemType,
        on: it.inventory_id == i.id and it.archived == false,
        where: i.user_id == ^user_id or not is_nil(m.id),
        group_by: i.id,
        select: {i, count(s.id, :distinct), count(it.id, :distinct)},
        order_by: i.name
      )
    )
  end

  @spec count_user_inventories(integer()) :: non_neg_integer()
  def count_user_inventories(user_id) do
    Repo.aggregate(from(i in Inv, where: i.user_id == ^user_id), :count)
  end

  @spec user_can_access?(integer(), integer()) :: boolean()
  def user_can_access?(user_id, inventory_id) do
    Repo.exists?(
      from(i in Inv,
        left_join: m in InventoryMember,
        on: m.inventory_id == i.id and m.user_id == ^user_id,
        where: i.id == ^inventory_id and (i.user_id == ^user_id or not is_nil(m.id))
      )
    )
  end

  @spec user_role_for_inventory(integer(), integer()) :: :owner | :viewer | :none
  def user_role_for_inventory(user_id, inventory_id) do
    case Repo.one(from(i in Inv, where: i.id == ^inventory_id, select: i.user_id)) do
      nil -> :none
      ^user_id -> :owner
      _other -> check_membership_role(user_id, inventory_id)
    end
  end

  @spec check_membership_role(integer(), integer()) :: :viewer | :none
  defp check_membership_role(user_id, inventory_id) do
    case Repo.one(
           from(m in InventoryMember,
             where: m.user_id == ^user_id and m.inventory_id == ^inventory_id,
             select: m.role
           )
         ) do
      nil -> :none
      _role -> :viewer
    end
  end

  @spec user_is_owner?(integer(), integer()) :: boolean()
  def user_is_owner?(user_id, inventory_id) do
    Repo.exists?(from(i in Inv, where: i.id == ^inventory_id and i.user_id == ^user_id))
  end

  @spec delete_inventory(Inv.t()) :: {:ok, Inv.t()} | {:error, Ecto.Changeset.t()}
  def delete_inventory(%Inv{} = inv), do: Repo.delete(inv)

  # Shelves

  @spec create_shelf(integer(), map()) :: {:ok, Shelf.t()} | {:error, Ecto.Changeset.t()}
  defp create_shelf(inventory_id, attrs) do
    %Shelf{}
    |> Shelf.changeset(Map.put(attrs, :inventory_id, inventory_id))
    |> Repo.insert()
  end

  @spec get_shelf!(integer()) :: Shelf.t()
  def get_shelf!(id), do: Repo.get!(Shelf, id)

  @spec create_shelf_with_bins(integer(), map(), pos_integer()) ::
          {:ok, Shelf.t()} | {:error, Ecto.Changeset.t()}
  def create_shelf_with_bins(inventory_id, shelf_attrs, bin_count) when bin_count >= 1 do
    Repo.transaction(fn ->
      case create_shelf(inventory_id, shelf_attrs) do
        {:ok, shelf} ->
          Enum.each(1..bin_count, fn bin_num ->
            create_bin_with_location(shelf, "#{bin_num}")
          end)

          Repo.preload(shelf, bins: :location)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @spec ensure_unsorted_shelf(integer()) :: {:ok, Shelf.t()} | {:error, term()}
  def ensure_unsorted_shelf(inventory_id) do
    unsorted_code = Shelf.unsorted_code()

    Repo.transaction(fn ->
      case Repo.get_by(Shelf, inventory_id: inventory_id, code: unsorted_code) do
        nil ->
          case %Shelf{}
               |> Shelf.changeset(%{
                 code: unsorted_code,
                 inventory_id: inventory_id,
                 system: true
               })
               |> Repo.insert(
                 on_conflict: :nothing,
                 conflict_target: [:inventory_id, :code]
               ) do
            {:ok, %Shelf{id: nil}} ->
              Shelf
              |> Repo.get_by!(inventory_id: inventory_id, code: unsorted_code)
              |> Repo.preload(bins: :location)

            {:ok, shelf} ->
              {:ok, _bin} = create_bin_with_location(shelf, "1")
              Repo.preload(shelf, bins: :location)

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        shelf ->
          Repo.preload(shelf, bins: :location)
      end
    end)
  end

  @spec get_unsorted_location(integer()) :: {:ok, Location.t()} | {:error, :no_bins}
  def get_unsorted_location(inventory_id) do
    case ensure_unsorted_shelf(inventory_id) do
      {:ok, shelf} ->
        case shelf.bins do
          [bin | _] -> {:ok, bin.location}
          [] -> {:error, :no_bins}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec add_bin_to_shelf(Shelf.t()) :: {:ok, Bin.t()} | {:error, :system_shelf} | {:error, Ecto.Changeset.t()}
  def add_bin_to_shelf(%Shelf{system: true}), do: {:error, :system_shelf}

  def add_bin_to_shelf(%Shelf{} = shelf) do
    next_bin_code = get_next_bin_code(shelf.id)

    Repo.transaction(fn ->
      case create_bin_with_location(shelf, next_bin_code) do
        {:ok, bin} -> bin
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @spec get_next_bin_code(integer()) :: String.t()
  defp get_next_bin_code(shelf_id) do
    existing_codes =
      from(b in Bin,
        where: b.shelf_id == ^shelf_id,
        select: fragment("CAST(? AS INTEGER)", b.code)
      )
      |> Repo.all()
      |> MapSet.new()

    first_gap(existing_codes, 1)
  end

  @spec first_gap(MapSet.t(integer()), integer()) :: String.t()
  defp first_gap(existing_codes, candidate) do
    if MapSet.member?(existing_codes, candidate) do
      first_gap(existing_codes, candidate + 1)
    else
      "#{candidate}"
    end
  end

  @spec create_bin_with_location(Shelf.t(), String.t()) ::
          {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  defp create_bin_with_location(shelf, bin_code) do
    with {:ok, bin} <- create_bin(%{code: bin_code, shelf_id: shelf.id}),
         full_code = "#{shelf.code}-#{bin_code}",
         {:ok, _location} <- create_location(%{full_code: full_code, bin_id: bin.id}) do
      {:ok, Repo.preload(bin, :location)}
    end
  end

  @spec rename_shelf(integer(), Shelf.t(), String.t()) ::
          {:ok, Shelf.t()} | {:error, :invalid_code | :code_exists | Ecto.Changeset.t()}
  def rename_shelf(inventory_id, %Shelf{} = shelf, new_code) do
    new_code = String.upcase(new_code)

    cond do
      not Shelf.valid_code?(new_code) ->
        {:error, :invalid_code}

      shelf.code == new_code ->
        {:ok, shelf}

      Repo.exists?(from(s in Shelf, where: s.inventory_id == ^inventory_id and s.code == ^new_code)) ->
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

  @spec list_shelves(integer()) :: [Shelf.t()]
  def list_shelves(inventory_id) do
    Repo.all(
      from(s in Shelf,
        where: s.inventory_id == ^inventory_id,
        order_by: s.code
      )
    )
  end

  @spec move_bin(Bin.t(), Shelf.t(), String.t()) ::
          {:ok, Bin.t()} | {:error, :invalid_code | :code_exists | Ecto.Changeset.t()}
  def move_bin(%Bin{} = bin, %Shelf{} = target_shelf, new_code) do
    cond do
      not Bin.valid_code?(new_code) ->
        {:error, :invalid_code}

      bin.shelf_id == target_shelf.id and bin.code == new_code ->
        {:ok, bin}

      Repo.exists?(from(b in Bin, where: b.shelf_id == ^target_shelf.id and b.code == ^new_code)) ->
        {:error, :code_exists}

      true ->
        do_move_bin(bin, target_shelf, new_code)
    end
  end

  @spec do_move_bin(Bin.t(), Shelf.t(), String.t()) ::
          {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  defp do_move_bin(bin, target_shelf, new_code) do
    new_full_code = "#{target_shelf.code}-#{new_code}"

    Repo.transaction(fn ->
      # Update the location full_code
      Repo.update_all(
        from(l in Location, where: l.bin_id == ^bin.id),
        set: [full_code: new_full_code]
      )

      # Update the bin code and shelf_id
      case Repo.update(Bin.changeset(bin, %{code: new_code, shelf_id: target_shelf.id})) do
        {:ok, updated_bin} -> updated_bin
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
          {:ok, Shelf.t()} | {:error, :has_items} | {:error, :system_shelf}
  def delete_empty_shelf(%Shelf{system: true}), do: {:error, :system_shelf}

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
        Repo.delete_all(from(b in Bin, where: b.shelf_id == ^shelf.id))

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

  # Locations

  @spec get_location!(integer()) :: Location.t()
  def get_location!(id), do: Repo.get!(Location, id)

  @spec list_location_codes(integer()) :: [String.t()]
  def list_location_codes(inventory_id) do
    Repo.all(
      from(l in Location,
        join: b in Bin,
        on: l.bin_id == b.id,
        join: s in Shelf,
        on: b.shelf_id == s.id,
        where: s.inventory_id == ^inventory_id,
        select: l.full_code,
        order_by: l.full_code
      )
    )
  end

  @spec create_location(map()) :: {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  defp create_location(attrs) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @spec ensure_location_with_code(integer(), String.t()) ::
          {:ok, Location.t()}
          | {:ok, Location.t(), integer()}
          | {:error, :invalid_format | Ecto.Changeset.t()}
  def ensure_location_with_code(inventory_id, location_code) do
    with {:ok, parsed} <- LocationParser.parse(location_code),
         {:ok, validation} <- LocationParser.validate(inventory_id, parsed) do
      case validation.status do
        :needs_creation ->
          create_hierarchy(inventory_id, parsed, validation.missing)

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
          | {:error, :invalid_format}
          | {:error, :shelf_not_found, String.t()}
          | {:error, :bin_not_found, String.t(), String.t()}

  @spec validate_location_code(integer(), String.t()) :: validate_location_result()
  def validate_location_code(inventory_id, location_code) do
    case LocationParser.parse(location_code) do
      {:error, :invalid_format} ->
        {:error, :invalid_format}

      {:ok, %{shelf_code: shelf_code, bin_code: bin_code}} ->
        validate_location_hierarchy(inventory_id, shelf_code, bin_code)
    end
  end

  @spec validate_location_hierarchy(integer(), String.t(), String.t()) ::
          validate_location_result()
  defp validate_location_hierarchy(inventory_id, shelf_code, bin_code) do
    shelf = Repo.get_by(Shelf, code: shelf_code, inventory_id: inventory_id)

    if is_nil(shelf) do
      {:error, :shelf_not_found, shelf_code}
    else
      validate_bin_and_location(shelf, bin_code)
    end
  end

  @spec validate_bin_and_location(Shelf.t(), String.t()) :: validate_location_result()
  defp validate_bin_and_location(shelf, bin_code) do
    bin = Repo.get_by(Bin, code: bin_code, shelf_id: shelf.id)

    if is_nil(bin) do
      {:error, :bin_not_found, shelf.code, bin_code}
    else
      location = Repo.get_by!(Location, bin_id: bin.id)
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

  @spec create_hierarchy(integer(), LocationParser.parsed(), [LocationParser.Missing.t()]) ::
          {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  defp create_hierarchy(inventory_id, %{shelf_code: shelf_code, bin_code: bin_code}, missing) do
    Repo.transaction(fn ->
      shelf = ensure_shelf(inventory_id, shelf_code, missing)
      bin = ensure_bin(bin_code, shelf, missing)
      ensure_location(shelf_code, bin_code, bin, missing)
    end)
  end

  @spec ensure_shelf(integer(), String.t(), [LocationParser.Missing.t()]) :: Shelf.t()
  defp ensure_shelf(inventory_id, shelf_code, missing) do
    if :shelf in missing do
      {:ok, shelf} = create_shelf(inventory_id, %{code: shelf_code})
      shelf
    else
      Repo.get_by!(Shelf, code: shelf_code, inventory_id: inventory_id)
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

  @spec ensure_location(String.t(), String.t(), Bin.t(), [LocationParser.Missing.t()]) :: Location.t()
  defp ensure_location(shelf_code, bin_code, bin, missing) do
    if :location in missing do
      full_code = "#{shelf_code}-#{bin_code}"
      {:ok, location} = create_location(%{full_code: full_code, bin_id: bin.id})
      location
    else
      Repo.get_by!(Location, bin_id: bin.id)
    end
  end

  @spec list_shelves_with_hierarchy(integer()) :: [Shelf.t()]
  def list_shelves_with_hierarchy(inventory_id) do
    bins_query = from(b in Bin, order_by: fragment("CAST(? AS INTEGER)", b.code))

    shelves_query =
      from(s in Shelf,
        where: s.inventory_id == ^inventory_id,
        order_by: [
          asc: fragment("length(?) - length(replace(?, '_', ''))", s.code, s.code),
          asc: fragment("regexp_replace(?, '[0-9]+$', '')", s.code),
          asc: fragment("COALESCE(NULLIF(regexp_replace(?, '^[^0-9]*', ''), '')::INTEGER, 0)", s.code)
        ]
      )

    shelves_query
    |> Repo.all()
    |> Repo.preload(bins: {bins_query, location: :item_types})
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

        location = Location |> Repo.get!(location_id) |> Repo.preload(bin: :shelf)
        bin = location.bin
        shelf = bin.shelf

        Repo.delete!(location)

        # Check if bin has any locations (each bin has only one location)
        bin_location_count =
          Repo.aggregate(from(l in Location, where: l.bin_id == ^bin.id), :count)

        if bin_location_count == 0 do
          Repo.delete!(bin)

          # Check if shelf has any bins with locations
          shelf_bin_count =
            Repo.aggregate(
              from(b in Bin,
                join: l in assoc(b, :location),
                where: b.shelf_id == ^shelf.id
              ),
              :count
            )

          if shelf_bin_count == 0 do
            # Delete all orphaned empty bins in the shelf
            Repo.delete_all(from(b in Bin, where: b.shelf_id == ^shelf.id))
            Repo.delete!(shelf)
          end
        end

        location
      end)
    end
  end

  @spec count_locations_by_occupancy(integer()) :: %{occupied: integer(), empty: integer()}
  def count_locations_by_occupancy(inventory_id) do
    Repo.one(
      from(l in Location,
        join: b in Bin,
        on: l.bin_id == b.id,
        join: s in Shelf,
        on: b.shelf_id == s.id,
        left_join: i in assoc(l, :item_types),
        where: s.inventory_id == ^inventory_id,
        where: is_nil(i.archived) or i.archived == false,
        select: %{
          occupied: fragment("COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END)", i.id, l.id),
          empty: fragment("COUNT(DISTINCT ?) - COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END)", l.id, i.id, l.id)
        }
      )
    ) || %{occupied: 0, empty: 0}
  end

  # ItemTypes

  @spec get_item_type!(integer()) :: ItemType.t()
  def get_item_type!(id), do: Repo.get!(ItemType, id)

  @spec get_item_type_with_location!(integer()) :: ItemType.t()
  def get_item_type_with_location!(id) do
    ItemType
    |> Repo.get!(id)
    |> Repo.preload(location: [bin: :shelf])
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

  @spec list_incomplete_items(integer(), [atom()]) :: [ItemType.t()]
  def list_incomplete_items(inventory_id, missing_fields) when is_list(missing_fields) do
    ItemType
    |> where([i], i.inventory_id == ^inventory_id)
    |> filter_by_archived(false)
    |> filter_by_missing_fields(missing_fields)
    |> order_by([i], asc: i.name)
    |> Repo.all()
    |> Repo.preload(location: [bin: :shelf])
  end

  @spec get_next_incomplete_item(integer(), integer(), [atom()]) :: ItemType.t() | nil
  def get_next_incomplete_item(inventory_id, current_id, missing_fields) when is_list(missing_fields) do
    current_item = Repo.get(ItemType, current_id)

    if is_nil(current_item) do
      nil
    else
      ItemType
      |> where([i], i.inventory_id == ^inventory_id)
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
  defp maybe_preload_location(item), do: Repo.preload(item, location: [bin: :shelf])

  @spec delete_item_type(ItemType.t()) :: {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def delete_item_type(%ItemType{} = item_type) do
    Repo.delete(item_type)
  end

  @spec archive_item_type(ItemType.t()) :: {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def archive_item_type(%ItemType{} = item) do
    item
    |> ItemType.changeset(%{
      quantity: 0,
      archived: true,
      location_id: nil
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

  @type item_attrs :: %{
          required(:inventory_id) => integer(),
          required(:location_code) => String.t(),
          required(:name) => String.t(),
          optional(:quantity) => integer(),
          optional(:description) => String.t() | nil,
          optional(:manufacturer) => String.t() | nil,
          optional(:model) => String.t() | nil,
          optional(:photo_path) => String.t() | nil,
          optional(:archived) => boolean(),
          optional(:metadata) => map()
        }

  @spec create_item_with_location(item_attrs()) ::
          {:ok, ItemType.t()} | {:error, :invalid_format | Ecto.Changeset.t()}
  def create_item_with_location(attrs) when is_map(attrs) do
    inventory_id = Map.fetch!(attrs, :inventory_id)
    location_code = Map.fetch!(attrs, :location_code)
    name = Map.fetch!(attrs, :name)

    item_attrs =
      attrs
      |> Map.drop([:inventory_id, :location_code])
      |> Map.put(:name, name)
      |> Map.put_new(:quantity, 1)
      |> Map.put_new(:archived, false)

    case ensure_location_with_code(inventory_id, location_code) do
      {:ok, location} ->
        create_item_type(Map.merge(item_attrs, %{inventory_id: inventory_id, location_id: location.id}))

      {:ok, location, _item_count} ->
        create_item_type(Map.merge(item_attrs, %{inventory_id: inventory_id, location_id: location.id}))

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create_item_with_location!(item_attrs()) :: ItemType.t()
  def create_item_with_location!(attrs) when is_map(attrs) do
    case create_item_with_location(attrs) do
      {:ok, item_type} -> item_type
      {:error, reason} -> raise "Could not create item with location: #{inspect(reason)}"
    end
  end

  @spec search_items(integer(), String.t(), keyword()) :: {[ItemType.t()], non_neg_integer()}
  def search_items(inventory_id, query, opts) do
    show_archived = Keyword.fetch!(opts, :show_archived)
    filters = Keyword.fetch!(opts, :filters)
    page = Keyword.fetch!(opts, :page)
    page_size = Keyword.fetch!(opts, :page_size)
    listing_types = Keyword.get(opts, :listing_types, [])

    if query == "" and filters == [] and listing_types == [] do
      {[], 0}
    else
      base_query =
        ItemType
        |> where([i], i.inventory_id == ^inventory_id)
        |> filter_by_archived(show_archived)
        |> filter_by_missing_fields(filters)
        |> filter_by_listing_types(listing_types)
        |> search_by_name(query)

      total_count = Repo.aggregate(base_query, :count)

      items =
        base_query
        |> apply_default_ordering(query)
        |> limit(^page_size)
        |> offset(^((page - 1) * page_size))
        |> Repo.all()
        |> Repo.preload(location: [bin: :shelf])

      {items, total_count}
    end
  end

  @spec list_all_items(integer(), keyword()) :: {[ItemType.t()], non_neg_integer()}
  def list_all_items(inventory_id, opts) do
    show_archived = Keyword.fetch!(opts, :show_archived)
    sort_by = Keyword.fetch!(opts, :sort_by)
    sort_order = Keyword.fetch!(opts, :sort_order)
    page = Keyword.fetch!(opts, :page)
    page_size = Keyword.fetch!(opts, :page_size)
    listing_types = Keyword.get(opts, :listing_types, [])

    base_query =
      ItemType
      |> where([i], i.inventory_id == ^inventory_id)
      |> filter_by_archived(show_archived)
      |> filter_by_listing_types(listing_types)

    total_count = Repo.aggregate(base_query, :count)

    items =
      base_query
      |> apply_sort(sort_by, sort_order)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()
      |> Repo.preload(location: [bin: :shelf])

    {items, total_count}
  end

  @spec list_all_items_unpaginated(integer(), keyword()) :: [ItemType.t()]
  def list_all_items_unpaginated(inventory_id, opts) do
    show_archived = Keyword.fetch!(opts, :show_archived)

    ItemType
    |> where([i], i.inventory_id == ^inventory_id)
    |> filter_by_archived(show_archived)
    |> order_by([i], asc: i.name)
    |> Repo.all()
    |> Repo.preload(location: [bin: :shelf])
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

  defp apply_sort(query, :model, order) do
    order_by(query, [i], [
      {^order, fragment("COALESCE(?, '')", i.model)},
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

  @spec filter_by_listing_types(Ecto.Queryable.t(), [String.t()]) :: Ecto.Queryable.t()
  defp filter_by_listing_types(query, []), do: query

  defp filter_by_listing_types(query, listing_types) do
    query
    |> join(:inner, [i], l in Listing, on: l.item_type_id == i.id and l.active == true and l.type in ^listing_types)
    |> distinct([i], i.id)
  end

  @spec search_by_name(Ecto.Queryable.t(), String.t()) :: Ecto.Queryable.t()
  defp search_by_name(query, ""), do: query

  defp search_by_name(query, search_query) do
    threshold = @similarity_threshold

    query
    |> where([i], fragment("similarity(?, ?) > ?", i.name, ^search_query, ^threshold))
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
      from(inst in ItemInstallation,
        where: inst.item_type_id == ^item.id,
        order_by: inst.project_name
      )
    )
  end

  @spec list_project_names(integer()) :: [String.t()]
  def list_project_names(inventory_id) do
    Repo.all(
      from(inst in ItemInstallation,
        join: i in ItemType,
        on: inst.item_type_id == i.id,
        where: i.inventory_id == ^inventory_id,
        distinct: inst.project_name,
        select: inst.project_name,
        order_by: inst.project_name
      )
    )
  end

  @spec list_items_in_project(integer(), String.t()) :: [{ItemInstallation.t(), ItemType.t()}]
  def list_items_in_project(inventory_id, project_name) do
    from(inst in ItemInstallation,
      join: item in assoc(inst, :item_type),
      where: item.inventory_id == ^inventory_id,
      where: inst.project_name == ^String.upcase(project_name),
      preload: [item_type: {item, location: [bin: :shelf]}],
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

  @spec project_has_archived_items?(integer(), String.t()) :: boolean()
  def project_has_archived_items?(inventory_id, project_name) do
    Repo.exists?(
      from(inst in ItemInstallation,
        join: item in assoc(inst, :item_type),
        where: item.inventory_id == ^inventory_id,
        where: inst.project_name == ^String.upcase(project_name),
        where: item.archived == true
      )
    )
  end

  @spec list_archived_items_in_project(integer(), String.t()) :: [ItemInstallation.t()]
  def list_archived_items_in_project(inventory_id, project_name) do
    Repo.all(
      from(inst in ItemInstallation,
        join: item in assoc(inst, :item_type),
        where: item.inventory_id == ^inventory_id,
        where: inst.project_name == ^String.upcase(project_name),
        where: item.archived == true,
        preload: [item_type: item],
        order_by: item.name
      )
    )
  end

  @spec uninstall_all_from_project(integer(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, :has_archived_items | term()}
  def uninstall_all_from_project(inventory_id, project_name) do
    if project_has_archived_items?(inventory_id, project_name) do
      {:error, :has_archived_items}
    else
      installations =
        Repo.all(
          from(inst in ItemInstallation,
            join: item in assoc(inst, :item_type),
            where: item.inventory_id == ^inventory_id,
            where: inst.project_name == ^String.upcase(project_name),
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

  @spec list_all_projects_with_items(integer()) :: [{String.t(), [ItemInstallation.t()]}]
  def list_all_projects_with_items(inventory_id) do
    from(inst in ItemInstallation,
      join: item in assoc(inst, :item_type),
      where: item.inventory_id == ^inventory_id,
      preload: [item_type: {item, location: [bin: :shelf]}],
      order_by: [inst.project_name, item.name]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.project_name)
    |> Enum.sort_by(fn {project_name, _} -> project_name end)
  end

  # Share Codes & Membership

  @spec create_share_code(integer(), integer()) :: {:ok, InventoryShareCode.t()} | {:error, Ecto.Changeset.t()}
  def create_share_code(inventory_id, created_by_id) do
    attrs = %{
      code: InventoryShareCode.generate_code(),
      role: "viewer",
      reusable: false,
      expires_at: InventoryShareCode.default_expiry(),
      inventory_id: inventory_id,
      created_by_id: created_by_id
    }

    %InventoryShareCode{}
    |> InventoryShareCode.changeset(attrs)
    |> Repo.insert()
  end

  @spec redeem_share_code(String.t(), integer()) ::
          {:ok, InventoryMember.t()} | {:error, :invalid_code | :already_member | :own_inventory}
  def redeem_share_code(code_str, user_id) do
    case Repo.one(from(sc in InventoryShareCode, where: sc.code == ^code_str, preload: :inventory)) do
      nil ->
        {:error, :invalid_code}

      share_code ->
        cond do
          not InventoryShareCode.valid?(share_code) ->
            {:error, :invalid_code}

          share_code.inventory.user_id == user_id ->
            {:error, :own_inventory}

          Repo.exists?(
            from(m in InventoryMember,
              where: m.user_id == ^user_id and m.inventory_id == ^share_code.inventory_id
            )
          ) ->
            {:error, :already_member}

          true ->
            Repo.transaction(fn ->
              case %InventoryMember{}
                   |> InventoryMember.changeset(%{
                     user_id: user_id,
                     inventory_id: share_code.inventory_id,
                     role: share_code.role
                   })
                   |> Repo.insert() do
                {:ok, member} ->
                  share_code
                  |> InventoryShareCode.changeset(%{
                    used_at: DateTime.truncate(DateTime.utc_now(), :second),
                    used_by_id: user_id
                  })
                  |> Repo.update!()

                  member

                {:error, _changeset} ->
                  Repo.rollback(:already_member)
              end
            end)
        end
    end
  end

  @spec get_share_code_info(String.t()) :: %{inventory_name: String.t(), shared_by: String.t(), role: String.t()} | nil
  def get_share_code_info(code_str) do
    case Repo.one(
           from(sc in InventoryShareCode,
             where: sc.code == ^code_str,
             preload: [:inventory, :created_by]
           )
         ) do
      nil ->
        nil

      share_code ->
        if InventoryShareCode.valid?(share_code) do
          %{
            inventory_name: share_code.inventory.name,
            shared_by: share_code.created_by.name,
            role: share_code.role
          }
        end
    end
  end

  @spec list_share_codes(integer()) :: [InventoryShareCode.t()]
  def list_share_codes(inventory_id) do
    Repo.all(
      from(sc in InventoryShareCode,
        where: sc.inventory_id == ^inventory_id and sc.reusable == false,
        order_by: [desc: sc.inserted_at],
        preload: [:created_by, :used_by]
      )
    )
  end

  # Public Links (reusable share codes for anonymous guest access)

  @spec create_public_link(integer(), integer()) :: {:ok, InventoryShareCode.t()} | {:error, Ecto.Changeset.t()}
  def create_public_link(inventory_id, created_by_id) do
    attrs = %{
      code: InventoryShareCode.generate_code(),
      role: "viewer",
      reusable: true,
      expires_at: InventoryShareCode.public_expiry(),
      inventory_id: inventory_id,
      created_by_id: created_by_id
    }

    %InventoryShareCode{}
    |> InventoryShareCode.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_public_link(integer()) :: InventoryShareCode.t() | nil
  def get_public_link(inventory_id) do
    Repo.one(
      from(sc in InventoryShareCode,
        where: sc.inventory_id == ^inventory_id and sc.reusable == true,
        where: sc.expires_at > ^DateTime.utc_now(),
        order_by: [desc: sc.inserted_at],
        limit: 1
      )
    )
  end

  @spec revoke_public_link(integer()) :: {:ok, InventoryShareCode.t()} | {:error, :not_found}
  def revoke_public_link(share_code_id) do
    case Repo.get(InventoryShareCode, share_code_id) do
      nil -> {:error, :not_found}
      share_code -> Repo.delete(share_code)
    end
  end

  @spec resolve_public_code(String.t()) :: {:ok, Inv.t()} | :invalid
  def resolve_public_code(code_str) do
    case Repo.one(
           from(sc in InventoryShareCode,
             where: sc.code == ^code_str and sc.reusable == true,
             preload: :inventory
           )
         ) do
      nil ->
        :invalid

      share_code ->
        if InventoryShareCode.valid?(share_code) do
          {:ok, share_code.inventory}
        else
          :invalid
        end
    end
  end

  @spec list_members(integer()) :: [InventoryMember.t()]
  def list_members(inventory_id) do
    Repo.all(
      from(m in InventoryMember,
        where: m.inventory_id == ^inventory_id,
        order_by: m.inserted_at,
        preload: :user
      )
    )
  end

  @spec remove_member(integer(), integer()) :: {:ok, InventoryMember.t()} | {:error, :not_found}
  def remove_member(inventory_id, user_id) do
    case Repo.one(
           from(m in InventoryMember,
             where: m.inventory_id == ^inventory_id and m.user_id == ^user_id
           )
         ) do
      nil -> {:error, :not_found}
      member -> Repo.delete(member)
    end
  end
end
