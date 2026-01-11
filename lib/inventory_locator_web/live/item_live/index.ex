defmodule InventoryLocatorWeb.ItemLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.ItemLive.Components

  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign_defaults(socket)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:query, query)
      |> perform_search()

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("toggle_archived", _params, socket) do
    socket =
      socket
      |> assign(:show_archived, !socket.assigns.show_archived)
      |> perform_search()

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("toggle_filter", %{"filter" => filter}, socket)
      when filter in ["manufacturer", "model", "description"] do
    filter_atom = String.to_existing_atom(filter)
    active_filters = toggle_filter_list(socket.assigns.active_filters, filter_atom)

    socket =
      socket
      |> assign(:active_filters, active_filters)
      |> perform_search()

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("toggle_filter", %{"filter" => _unknown}, socket) do
    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("open_item_modal", %{"id" => id}, socket) do
    item_id = String.to_integer(id)

    socket =
      if socket.assigns.active_filters == [] do
        socket
        |> assign(:selected_item_id, item_id)
        |> assign(:batch_mode, false)
        |> assign(:batch_item_ids, [])
      else
        batch_ids = Enum.map(socket.assigns.results, & &1.id)

        socket
        |> assign(:selected_item_id, item_id)
        |> assign(:batch_mode, true)
        |> assign(:batch_item_ids, batch_ids)
      end

    {:noreply, socket}
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:close_item_modal}, socket) do
    {:noreply, socket |> reset_batch_state() |> perform_search()}
  end

  @impl true
  @spec handle_info({:item_deleted, String.t()}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:item_deleted, item_name}, socket) do
    socket =
      socket
      |> reset_batch_state()
      |> perform_search()
      |> put_flash(:info, "Deleted: #{item_name}")

    {:noreply, socket}
  end

  @impl true
  @spec handle_info({:advance_to_next_incomplete}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:advance_to_next_incomplete}, socket) do
    socket = perform_search(socket)

    socket =
      case socket.assigns.results do
        [] ->
          socket
          |> reset_batch_state()
          |> put_flash(:info, "All items complete!")

        [next | _] = results ->
          socket
          |> assign(:selected_item_id, next.id)
          |> assign(:batch_item_ids, Enum.map(results, & &1.id))
      end

    {:noreply, socket}
  end

  @spec assign_defaults(Socket.t()) :: Socket.t()
  defp assign_defaults(socket) do
    socket
    |> assign(:query, "")
    |> assign(:results, [])
    |> assign(:show_archived, false)
    |> assign(:active_filters, [])
    |> assign(:page_title, "Search Items")
    |> reset_batch_state()
  end

  @spec reset_batch_state(Socket.t()) :: Socket.t()
  defp reset_batch_state(socket) do
    socket
    |> assign(:selected_item_id, nil)
    |> assign(:batch_mode, false)
    |> assign(:batch_item_ids, [])
  end

  @spec perform_search(Socket.t()) :: Socket.t()
  defp perform_search(socket) do
    results =
      Inventory.search_items(
        socket.assigns.query,
        show_archived: socket.assigns.show_archived,
        filters: socket.assigns.active_filters
      )

    assign(socket, :results, results)
  end

  @spec toggle_filter_list([atom()], atom()) :: [atom()]
  defp toggle_filter_list(filters, filter) do
    if filter in filters do
      List.delete(filters, filter)
    else
      [filter | filters]
    end
  end
end
