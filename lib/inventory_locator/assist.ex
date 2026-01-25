defmodule InventoryLocator.Assist do
  @moduledoc false
  import Ecto.Query

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Repo
  alias Phoenix.PubSub

  @pubsub InventoryLocator.PubSub
  @topic "assist:display"

  @type item_summary :: %{
          id: integer(),
          name: String.t(),
          manufacturer: String.t() | nil,
          model: String.t() | nil,
          description: String.t() | nil,
          photo_path: String.t() | nil,
          location_code: String.t() | nil,
          missing_fields: [atom()]
        }

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  @spec list_incomplete_items(integer(), map()) :: [item_summary()]
  def list_incomplete_items(inventory_id, opts) do
    fields = Map.get(opts, :fields, [:manufacturer, :model, :description])
    limit = Map.get(opts, :limit, 50)

    ItemType
    |> where([i], i.inventory_id == ^inventory_id)
    |> where([i], i.archived == false)
    |> filter_incomplete(fields)
    |> order_by([i], asc: i.name)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(location: [bin: :shelf])
    |> Enum.map(&to_summary(&1, fields))
  end

  @spec show_item(integer()) :: :ok
  def show_item(item_id) do
    PubSub.broadcast(@pubsub, @topic, {:show_item, item_id})
  end

  @spec get_item(integer()) :: {:ok, item_summary()} | {:error, :not_found}
  def get_item(item_id) do
    case Repo.get(ItemType, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        item = Repo.preload(item, location: [bin: :shelf])
        {:ok, to_summary(item, [:manufacturer, :model, :description])}
    end
  end

  @spec update_item(integer(), map()) :: {:ok, ItemType.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_item(item_id, attrs) do
    case Repo.get(ItemType, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        Inventory.update_item_type(item, attrs)
    end
  end

  @spec skip_field(integer(), atom()) :: {:ok, ItemType.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def skip_field(item_id, field) when field in [:manufacturer, :model, :description] do
    case Repo.get(ItemType, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        metadata = item.metadata || %{}
        skip_key = "#{field}_skipped"
        new_metadata = Map.put(metadata, skip_key, true)
        Inventory.update_item_type(item, %{metadata: new_metadata})
    end
  end

  @spec skip_fields(integer(), [atom()]) :: {:ok, ItemType.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def skip_fields(item_id, fields) when is_list(fields) do
    case Repo.get(ItemType, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        metadata = item.metadata || %{}

        new_metadata =
          Enum.reduce(fields, metadata, fn field, acc ->
            if field in [:manufacturer, :model, :description] do
              Map.put(acc, "#{field}_skipped", true)
            else
              acc
            end
          end)

        Inventory.update_item_type(item, %{metadata: new_metadata})
    end
  end

  @spec unskip_field(integer(), atom()) :: {:ok, ItemType.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def unskip_field(item_id, field) when field in [:manufacturer, :model, :description] do
    case Repo.get(ItemType, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        metadata = item.metadata || %{}
        skip_key = "#{field}_skipped"
        new_metadata = Map.delete(metadata, skip_key)
        Inventory.update_item_type(item, %{metadata: new_metadata})
    end
  end

  @spec filter_incomplete(Ecto.Queryable.t(), [atom()]) :: Ecto.Queryable.t()
  defp filter_incomplete(query, fields) do
    conditions =
      Enum.map(fields, fn field ->
        skip_key = "#{field}_skipped"

        dynamic(
          [i],
          is_nil(field(i, ^field)) and
            (is_nil(i.metadata) or
               fragment("NOT coalesce(?->>? = 'true', false)", i.metadata, ^skip_key))
        )
      end)

    combined =
      Enum.reduce(conditions, fn condition, acc ->
        dynamic([], ^acc or ^condition)
      end)

    where(query, ^combined)
  end

  @spec to_summary(ItemType.t(), [atom()]) :: item_summary()
  defp to_summary(item, check_fields) do
    location_code =
      if item.location do
        item.location.full_code
      end

    missing = compute_missing_fields(item, check_fields)

    %{
      id: item.id,
      name: item.name,
      manufacturer: item.manufacturer,
      model: item.model,
      description: item.description,
      photo_path: item.photo_path,
      location_code: location_code,
      missing_fields: missing
    }
  end

  @spec compute_missing_fields(ItemType.t(), [atom()]) :: [atom()]
  defp compute_missing_fields(item, check_fields) do
    metadata = item.metadata || %{}

    Enum.filter(check_fields, fn field ->
      value = Map.get(item, field)
      skip_key = "#{field}_skipped"
      skipped = Map.get(metadata, skip_key, false)

      is_nil(value) and not skipped
    end)
  end
end
