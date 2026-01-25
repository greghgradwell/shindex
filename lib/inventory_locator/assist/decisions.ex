defmodule InventoryLocator.Assist.Decisions do
  @moduledoc false
  use Agent

  @type item_decision :: %{
          item_id: integer(),
          item_name: String.t(),
          find: [atom()],
          skip: [atom()]
        }

  @type batch :: %{
          batch_id: String.t(),
          items: [item_decision()],
          submitted_at: DateTime.t() | nil
        }

  @spec start_link(term()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end

  @spec start_batch([map()]) :: :ok
  def start_batch(items) when is_list(items) do
    batch = %{
      batch_id: generate_batch_id(),
      items: Enum.map(items, &to_item_decision/1),
      submitted_at: nil
    }

    Agent.update(__MODULE__, fn _ -> batch end)
  end

  @spec update_item(integer(), [atom()], [atom()]) :: :ok | {:error, :no_batch | :item_not_found}
  def update_item(item_id, find_fields, skip_fields) do
    Agent.get_and_update(__MODULE__, fn
      nil ->
        {{:error, :no_batch}, nil}

      batch ->
        case find_item_index(batch.items, item_id) do
          nil ->
            {{:error, :item_not_found}, batch}

          index ->
            updated_items =
              List.update_at(batch.items, index, fn item ->
                %{item | find: find_fields, skip: skip_fields}
              end)

            {:ok, %{batch | items: updated_items}}
        end
    end)
  end

  @spec submit_batch() :: :ok | {:error, :no_batch}
  def submit_batch do
    Agent.get_and_update(__MODULE__, fn
      nil ->
        {{:error, :no_batch}, nil}

      batch ->
        {:ok, %{batch | submitted_at: DateTime.utc_now()}}
    end)
  end

  @spec get_batch() :: batch() | nil
  def get_batch do
    Agent.get(__MODULE__, & &1)
  end

  @spec get_decisions() :: batch() | nil
  def get_decisions do
    case Agent.get(__MODULE__, & &1) do
      %{submitted_at: nil} -> nil
      batch -> batch
    end
  end

  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn _ -> nil end)
  end

  @spec generate_batch_id() :: String.t()
  defp generate_batch_id do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @spec to_item_decision(map()) :: item_decision()
  defp to_item_decision(item) do
    %{
      item_id: item.id,
      item_name: item.name,
      find: item.missing_fields,
      skip: []
    }
  end

  @spec find_item_index([item_decision()], integer()) :: non_neg_integer() | nil
  defp find_item_index(items, item_id) do
    Enum.find_index(items, fn item -> item.item_id == item_id end)
  end
end
