defmodule InventoryLocatorWeb.LocationLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.LocationLive.Components

  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    shelves = Inventory.list_shelves_with_hierarchy()
    stats = Inventory.count_locations_by_occupancy()

    {:ok,
     socket
     |> assign(:shelves, shelves)
     |> assign(:stats, stats)
     |> assign(:page_title, "Location Management")}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
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
end
