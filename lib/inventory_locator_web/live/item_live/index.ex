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

  def handle_event("open_item_modal", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_item_id, String.to_integer(id))}
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:close_item_modal}, socket) do
    socket =
      socket
      |> assign(:selected_item_id, nil)
      |> perform_search()

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
    |> assign(:selected_item_id, nil)
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
