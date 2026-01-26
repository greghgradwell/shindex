defmodule InventoryLocator.Assist.Decisions do
  @moduledoc false
  use Agent

  @type item_decision :: %{
          item_id: integer(),
          item_name: String.t(),
          find: [atom()],
          skip: [atom()]
        }

  @type item_suggestions :: %{integer() => %{atom() => String.t()}}

  @type batch :: %{
          batch_id: String.t(),
          items: [item_decision()],
          submitted_at: DateTime.t() | nil,
          suggestions: item_suggestions(),
          review_ready_at: DateTime.t() | nil,
          review_submitted_at: DateTime.t() | nil,
          accepted: item_suggestions() | nil
        }

  @type review :: %{
          item_id: integer(),
          suggestions: %{atom() => String.t()},
          submitted_at: DateTime.t() | nil,
          accepted: %{atom() => String.t()} | nil
        }

  @type state :: %{
          batch: batch() | nil,
          review: review() | nil
        }

  @spec start_link(term()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{batch: nil, review: nil} end, name: __MODULE__)
  end

  # ============================================================
  # Batch functions
  # ============================================================

  @spec start_batch([map()]) :: :ok
  def start_batch(items) when is_list(items) do
    batch = %{
      batch_id: generate_batch_id(),
      items: Enum.map(items, &to_item_decision/1),
      submitted_at: nil,
      suggestions: %{},
      review_ready_at: nil,
      review_submitted_at: nil,
      accepted: nil
    }

    Agent.update(__MODULE__, fn state -> %{state | batch: batch} end, 1000)
  end

  @spec update_item(integer(), [atom()], [atom()]) :: :ok | {:error, :no_batch | :item_not_found}
  def update_item(item_id, find_fields, skip_fields) do
    Agent.get_and_update(
      __MODULE__,
      fn state ->
        case state.batch do
          nil ->
            {{:error, :no_batch}, state}

          batch ->
            case find_item_index(batch.items, item_id) do
              nil ->
                {{:error, :item_not_found}, state}

              index ->
                updated_items =
                  List.update_at(batch.items, index, fn item ->
                    %{item | find: find_fields, skip: skip_fields}
                  end)

                {:ok, %{state | batch: %{batch | items: updated_items}}}
            end
        end
      end,
      1000
    )
  end

  @spec submit_batch() :: :ok | {:error, :no_batch}
  def submit_batch do
    Agent.get_and_update(__MODULE__, fn state ->
      case state.batch do
        nil ->
          {{:error, :no_batch}, state}

        batch ->
          {:ok, %{state | batch: %{batch | submitted_at: DateTime.utc_now()}}}
      end
    end)
  end

  @spec get_batch() :: batch() | nil
  def get_batch do
    Agent.get(__MODULE__, fn state -> state.batch end)
  end

  @spec get_decisions() :: batch() | nil
  def get_decisions do
    Agent.get(__MODULE__, fn state ->
      case state.batch do
        %{submitted_at: nil} -> nil
        batch -> batch
      end
    end)
  end

  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn state -> %{state | batch: nil} end)
  end

  # ============================================================
  # Batch review functions
  # ============================================================

  @spec add_suggestions(integer(), %{atom() => String.t()}) ::
          :ok | {:error, :no_batch | :item_not_in_batch}
  def add_suggestions(item_id, suggestions) when is_integer(item_id) and is_map(suggestions) do
    Agent.get_and_update(
      __MODULE__,
      fn state ->
        case state.batch do
          nil ->
            {{:error, :no_batch}, state}

          batch ->
            if Enum.any?(batch.items, fn item -> item.item_id == item_id end) do
              updated_suggestions = Map.put(batch.suggestions, item_id, suggestions)
              {:ok, %{state | batch: %{batch | suggestions: updated_suggestions}}}
            else
              {{:error, :item_not_in_batch}, state}
            end
        end
      end,
      1000
    )
  end

  @spec mark_review_ready() :: :ok | {:error, :no_batch}
  def mark_review_ready do
    Agent.get_and_update(__MODULE__, fn state ->
      case state.batch do
        nil ->
          {{:error, :no_batch}, state}

        batch ->
          {:ok, %{state | batch: %{batch | review_ready_at: DateTime.utc_now()}}}
      end
    end)
  end

  @spec get_batch_suggestions() :: %{batch: batch(), items: [map()]} | nil
  def get_batch_suggestions do
    Agent.get(__MODULE__, fn state ->
      case state.batch do
        %{review_ready_at: ready_at} = batch when not is_nil(ready_at) ->
          %{batch: batch, items: batch.items}

        _other ->
          nil
      end
    end)
  end

  @spec submit_batch_review(item_suggestions()) :: :ok | {:error, :no_batch | :not_ready}
  def submit_batch_review(accepted) when is_map(accepted) do
    Agent.get_and_update(
      __MODULE__,
      fn state ->
        case state.batch do
          nil ->
            {{:error, :no_batch}, state}

          %{review_ready_at: nil} ->
            {{:error, :not_ready}, state}

          batch ->
            updated_batch = %{
              batch
              | review_submitted_at: DateTime.utc_now(),
                accepted: accepted
            }

            {:ok, %{state | batch: updated_batch}}
        end
      end,
      1000
    )
  end

  @spec get_batch_review_decision() :: %{batch_id: String.t(), accepted: item_suggestions()} | nil
  def get_batch_review_decision do
    Agent.get(__MODULE__, fn state ->
      case state.batch do
        %{review_submitted_at: submitted_at, accepted: accepted, batch_id: batch_id}
        when not is_nil(submitted_at) ->
          %{batch_id: batch_id, accepted: accepted}

        _other ->
          nil
      end
    end)
  end

  # ============================================================
  # Review functions (single-item - legacy)
  # ============================================================

  @spec start_review(integer(), %{atom() => String.t()}) :: :ok
  def start_review(item_id, suggestions) when is_integer(item_id) and is_map(suggestions) do
    review = %{
      item_id: item_id,
      suggestions: suggestions,
      submitted_at: nil,
      accepted: nil
    }

    Agent.update(__MODULE__, fn state -> %{state | review: review} end)
  end

  @spec submit_review(%{atom() => String.t()}) :: :ok | {:error, :no_review}
  def submit_review(accepted) when is_map(accepted) do
    Agent.get_and_update(__MODULE__, fn state ->
      case state.review do
        nil ->
          {{:error, :no_review}, state}

        review ->
          updated_review = %{review | submitted_at: DateTime.utc_now(), accepted: accepted}
          {:ok, %{state | review: updated_review}}
      end
    end)
  end

  @spec get_review() :: review() | nil
  def get_review do
    Agent.get(__MODULE__, fn state -> state.review end)
  end

  @spec get_review_decision() :: review() | nil
  def get_review_decision do
    Agent.get(__MODULE__, fn state ->
      case state.review do
        %{submitted_at: nil} -> nil
        review -> review
      end
    end)
  end

  @spec clear_review() :: :ok
  def clear_review do
    Agent.update(__MODULE__, fn state -> %{state | review: nil} end)
  end

  # ============================================================
  # Private helpers
  # ============================================================

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
