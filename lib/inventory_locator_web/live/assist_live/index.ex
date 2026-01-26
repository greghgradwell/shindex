defmodule InventoryLocatorWeb.AssistLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Assist
  alias InventoryLocator.Assist.Decisions
  alias InventoryLocator.Inventory
  alias InventoryLocatorWeb.AssistHelpers
  alias Phoenix.LiveView.Socket

  require Logger

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    _ = if connected?(socket), do: Assist.subscribe()

    socket =
      socket
      |> assign(:page_title, "Assist Mode")
      |> assign(:current_item, nil)
      |> assign(:batch_items, [])
      |> assign(:decisions, %{})
      |> assign(:suggestions, %{})
      |> assign(:review_accepted, %{})
      |> assign(:batch_review_items, [])
      |> assign(:batch_review_accepted, %{})
      |> restore_state_if_exists()

    {:ok, socket}
  end

  @spec restore_state_if_exists(Socket.t()) :: Socket.t()
  defp restore_state_if_exists(socket) do
    case Decisions.get_review() do
      %{submitted_at: nil} = review ->
        restore_review_state(socket, review)

      _no_active_review ->
        restore_batch_if_exists(socket)
    end
  end

  @spec restore_review_state(Socket.t(), Decisions.review()) :: Socket.t()
  defp restore_review_state(socket, review) do
    case Assist.get_item(review.item_id) do
      {:ok, item} ->
        review_accepted = init_review_accepted(review.suggestions)

        socket
        |> assign(:current_item, item)
        |> assign(:suggestions, review.suggestions)
        |> assign(:review_accepted, review_accepted)
        |> assign(:mode, :review)

      {:error, :not_found} ->
        Decisions.clear_review()
        restore_batch_if_exists(socket)
    end
  end

  @spec restore_batch_if_exists(Socket.t()) :: Socket.t()
  defp restore_batch_if_exists(socket) do
    case Decisions.get_batch() do
      nil ->
        assign(socket, :mode, :waiting)

      %{review_ready_at: ready_at} = batch when not is_nil(ready_at) ->
        restore_batch_review_state(socket, batch)

      %{submitted_at: submitted_at} = batch when not is_nil(submitted_at) ->
        item_ids = Enum.map(batch.items, & &1.item_id)
        items = Assist.get_items_by_ids(item_ids)
        decisions = restore_decisions(batch.items)

        socket
        |> assign(:batch_items, items)
        |> assign(:decisions, decisions)
        |> assign(:mode, :submitted)

      batch ->
        item_ids = Enum.map(batch.items, & &1.item_id)
        items = Assist.get_items_by_ids(item_ids)
        decisions = restore_decisions(batch.items)

        socket
        |> assign(:batch_items, items)
        |> assign(:decisions, decisions)
        |> assign(:mode, :batch)
    end
  end

  @spec restore_batch_review_state(Socket.t(), Decisions.batch()) :: Socket.t()
  defp restore_batch_review_state(socket, batch) do
    item_ids = Enum.map(batch.items, & &1.item_id)
    items = Assist.get_items_by_ids(item_ids)
    items_by_id = Map.new(items, fn item -> {item.id, item} end)

    items_with_suggestions =
      Enum.flat_map(batch.suggestions, fn {item_id, suggestions} ->
        case Map.get(items_by_id, item_id) do
          nil -> []
          item -> [{item, suggestions}]
        end
      end)

    batch_review_accepted = init_batch_review_accepted(items_with_suggestions)

    socket
    |> assign(:batch_review_items, items_with_suggestions)
    |> assign(:batch_review_accepted, batch_review_accepted)
    |> assign(:mode, :batch_reviewing)
  end

  @spec init_batch_review_accepted([{map(), map()}]) :: map()
  defp init_batch_review_accepted(items_with_suggestions) do
    Map.new(items_with_suggestions, fn {item, suggestions} ->
      field_state =
        Map.new(suggestions, fn {field, value} ->
          {field, %{enabled: true, value: value}}
        end)

      {item.id, field_state}
    end)
  end

  @spec restore_decisions([Decisions.item_decision()]) :: map()
  defp restore_decisions(batch_items) do
    Map.new(batch_items, fn item ->
      {item.item_id, %{find: item.find, skip: item.skip}}
    end)
  end

  @spec init_review_accepted(%{atom() => String.t()}) :: %{atom() => %{enabled: boolean(), value: String.t()}}
  defp init_review_accepted(suggestions) do
    Map.new(suggestions, fn {field, value} ->
      {field, %{enabled: true, value: value}}
    end)
  end

  # ============================================================
  # Event handlers
  # ============================================================

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("toggle_field", %{"item-id" => item_id_str, "field" => field_str}, socket) do
    with {item_id, ""} <- Integer.parse(item_id_str),
         {:ok, field} <- AssistHelpers.safe_to_field_atom(field_str) do
      decisions = socket.assigns.decisions
      item_decisions = Map.get(decisions, item_id, %{find: [], skip: []})

      updated_decisions =
        if field in item_decisions.find do
          %{
            item_decisions
            | find: List.delete(item_decisions.find, field),
              skip: [field | item_decisions.skip]
          }
        else
          %{
            item_decisions
            | find: [field | item_decisions.find],
              skip: List.delete(item_decisions.skip, field)
          }
        end

      new_decisions = Map.put(decisions, item_id, updated_decisions)
      _ = Decisions.update_item(item_id, updated_decisions.find, updated_decisions.skip)

      {:noreply, assign(socket, :decisions, new_decisions)}
    else
      invalid_input ->
        Logger.warning("Invalid toggle_field event: #{inspect(invalid_input)}")
        {:noreply, socket}
    end
  end

  def handle_event("submit_batch", _params, socket) do
    _ = Decisions.submit_batch()
    {:noreply, assign(socket, :mode, :submitted)}
  end

  def handle_event("toggle_review_field", %{"field" => field_str}, socket) do
    case AssistHelpers.safe_to_field_atom(field_str) do
      {:ok, field} ->
        review_accepted = socket.assigns.review_accepted

        case Map.get(review_accepted, field) do
          nil ->
            {:noreply, socket}

          current ->
            updated = %{current | enabled: not current.enabled}
            {:noreply, assign(socket, :review_accepted, Map.put(review_accepted, field, updated))}
        end

      {:error, :invalid_field} ->
        Logger.warning("Invalid field in toggle_review_field: #{inspect(field_str)}")
        {:noreply, socket}
    end
  end

  def handle_event("submit_review", params, socket) do
    accepted = extract_accepted_from_form(params, socket.assigns.suggestions)
    _ = Decisions.submit_review(accepted)
    {:noreply, assign(socket, :mode, :review_submitted)}
  end

  def handle_event("update_source_url", %{"value" => url, "item-id" => item_id_str}, socket) do
    case Integer.parse(item_id_str) do
      {item_id, ""} ->
        url_value = if url == "", do: nil, else: url

        case Assist.update_item(item_id, %{source_url: url_value}) do
          {:ok, _item} ->
            batch_items =
              Enum.map(socket.assigns.batch_items, fn item ->
                if item.id == item_id, do: %{item | source_url: url_value}, else: item
              end)

            {:noreply, assign(socket, :batch_items, batch_items)}

          {:error, _reason} ->
            {:noreply, socket}
        end

      invalid_input ->
        Logger.warning("Invalid update_source_url event: #{inspect(invalid_input)}")
        {:noreply, socket}
    end
  end

  def handle_event("update_source_url", %{"value" => url}, socket) do
    item_id = socket.assigns.current_item.id
    url_value = if url == "", do: nil, else: url

    case Assist.update_item(item_id, %{source_url: url_value}) do
      {:ok, _item} ->
        updated_item = Map.put(socket.assigns.current_item, :source_url, url_value)
        {:noreply, assign(socket, :current_item, updated_item)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_batch_review_field", %{"item-id" => item_id_str, "field" => field_str}, socket) do
    with {item_id, ""} <- Integer.parse(item_id_str),
         {:ok, field} <- AssistHelpers.safe_to_field_atom(field_str) do
      batch_review_accepted = socket.assigns.batch_review_accepted

      case get_in(batch_review_accepted, [item_id, field]) do
        nil ->
          {:noreply, socket}

        current ->
          updated = %{current | enabled: not current.enabled}
          new_accepted = put_in(batch_review_accepted, [item_id, field], updated)
          {:noreply, assign(socket, :batch_review_accepted, new_accepted)}
      end
    else
      invalid_input ->
        Logger.warning("Invalid toggle_batch_review_field event: #{inspect(invalid_input)}")
        {:noreply, socket}
    end
  end

  def handle_event("submit_batch_review", params, socket) do
    accepted = extract_batch_accepted_from_form(params, socket.assigns.batch_review_items)
    _ = Decisions.submit_batch_review(accepted)
    {:noreply, assign(socket, :mode, :batch_review_submitted)}
  end

  def handle_event(event, params, socket) do
    Logger.warning("Unexpected event: #{inspect(event)}, params: #{inspect(params)}")
    {:noreply, socket}
  end

  # ============================================================
  # PubSub message handlers
  # ============================================================

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:show_item, item_id}, socket) do
    item = Inventory.get_item_type_with_location!(item_id)

    socket =
      socket
      |> assign(:current_item, item)
      |> assign(:suggestions, %{})
      |> assign(:review_accepted, %{})
      |> assign(:mode, :review)

    {:noreply, socket}
  end

  def handle_info({:show_batch, items}, socket) do
    decisions =
      Map.new(items, fn item ->
        {item.id, %{find: item.missing_fields, skip: []}}
      end)

    socket =
      socket
      |> assign(:batch_items, items)
      |> assign(:decisions, decisions)
      |> assign(:mode, :batch)

    {:noreply, socket}
  end

  def handle_info({:show_review, item, suggestions}, socket) do
    review_accepted = init_review_accepted(suggestions)

    socket =
      socket
      |> assign(:current_item, item)
      |> assign(:suggestions, suggestions)
      |> assign(:review_accepted, review_accepted)
      |> assign(:mode, :review)

    {:noreply, socket}
  end

  def handle_info({:show_batch_review, items_with_suggestions}, socket) do
    batch_review_accepted = init_batch_review_accepted(items_with_suggestions)

    socket =
      socket
      |> assign(:batch_review_items, items_with_suggestions)
      |> assign(:batch_review_accepted, batch_review_accepted)
      |> assign(:mode, :batch_reviewing)

    {:noreply, socket}
  end

  def handle_info(message, socket) do
    Logger.warning("Unexpected message: #{inspect(message)}")
    {:noreply, socket}
  end

  # ============================================================
  # Private helpers
  # ============================================================

  @spec extract_accepted_from_form(map(), map()) :: %{atom() => String.t()}
  defp extract_accepted_from_form(params, suggestions) do
    suggestions
    |> Map.keys()
    |> Enum.filter(fn field -> Map.has_key?(params, "enabled_#{field}") end)
    |> Map.new(fn field ->
      value = Map.get(params, "value_#{field}", "")
      {field, value}
    end)
  end

  @spec extract_batch_accepted_from_form(map(), [{map(), map()}]) :: %{integer() => %{atom() => String.t()}}
  defp extract_batch_accepted_from_form(params, items_with_suggestions) do
    Map.new(items_with_suggestions, fn {item, suggestions} ->
      accepted_fields =
        suggestions
        |> Map.keys()
        |> Enum.filter(fn field -> Map.has_key?(params, "enabled_#{item.id}_#{field}") end)
        |> Map.new(fn field ->
          value = Map.get(params, "value_#{item.id}_#{field}", "")
          {field, value}
        end)

      {item.id, accepted_fields}
    end)
  end
end
