defmodule InventoryLocatorWeb.LocationLive.Index do
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.{Inventory, Repo}
  import InventoryLocatorWeb.LocationLive.Components

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    shelves = Inventory.list_shelves_with_hierarchy()
    stats = Inventory.count_locations_by_occupancy()

    {:ok,
     socket
     |> assign(:shelves, shelves)
     |> assign(:stats, stats)
     |> assign(:quickview_location, nil)
     |> assign(:page_title, "Location Management")}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("delete_location", %{"id" => id}, socket) when is_integer(id) do
    case Inventory.delete_empty_location(id) do
      {:ok, _location} ->
        shelves = Inventory.list_shelves_with_hierarchy()
        stats = Inventory.count_locations_by_occupancy()

        {:noreply,
         socket
         |> assign(:shelves, shelves)
         |> assign(:stats, stats)
         |> put_flash(:info, "Location deleted successfully")}

      {:error, :occupied} ->
        {:noreply, put_flash(socket, :error, "Cannot delete occupied location")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete location")}
    end
  end

  def handle_event("show_quickview", %{"location_id" => id}, socket) do
    location =
      Inventory.get_location!(id)
      |> Repo.preload([:item_types, cell: [bin: :shelf]])

    {:noreply, assign(socket, :quickview_location, location)}
  end

  def handle_event("close_quickview", _params, socket) do
    {:noreply, assign(socket, :quickview_location, nil)}
  end
end
