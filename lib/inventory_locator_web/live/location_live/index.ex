defmodule InventoryLocatorWeb.LocationLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.LocationLive.Components

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Shelf
  alias InventoryLocatorWeb.ItemLive.ShowModal
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
     |> assign(:page_title, "Location Management")
     |> assign(:selected_item_id, nil)
     |> assign(:show_cells, true)
     |> assign(:show_create_shelf_modal, false)
     |> assign(:show_rename_shelf_modal, false)
     |> assign(:rename_shelf, nil)
     |> assign(:rename_shelf_location_count, 0)
     |> assign(:shelf_code_error, nil)}
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

  def handle_event("open_item_modal", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_item_id, String.to_integer(id))}
  end

  def handle_event("toggle_cells", _params, socket) do
    new_value = !socket.assigns.show_cells

    {:noreply,
     socket
     |> assign(:show_cells, new_value)
     |> push_event("persist_toggle", %{key: "show_cells", value: new_value})}
  end

  def handle_event("restore_toggle", %{"key" => "show_cells", "value" => value}, socket) do
    {:noreply, assign(socket, :show_cells, value)}
  end

  def handle_event("show_create_shelf_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_shelf_modal, true)
     |> assign(:shelf_code_error, nil)}
  end

  def handle_event("close_create_shelf_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_shelf_modal, false)
     |> assign(:shelf_code_error, nil)}
  end

  def handle_event("validate_shelf_code", params, socket) do
    code = params["code"] || params["new_code"] || ""

    error =
      cond do
        code == "" ->
          nil

        not Shelf.valid_code?(code) ->
          "Must start with a letter and contain only letters, numbers, and underscores"

        true ->
          nil
      end

    {:noreply, assign(socket, :shelf_code_error, error)}
  end

  def handle_event("create_shelf", %{"code" => code, "bin_count" => bin_count_str}, socket) do
    bin_count = String.to_integer(bin_count_str)
    shelf_code = String.upcase(code)

    case Inventory.create_shelf_with_bins(%{code: shelf_code}, bin_count) do
      {:ok, _shelf} ->
        {:noreply,
         socket
         |> refresh_data()
         |> assign(:show_create_shelf_modal, false)
         |> assign(:shelf_code_error, nil)
         |> put_flash(:info, "Shelf #{shelf_code} created with #{bin_count} bin(s)")}

      {:error, changeset} ->
        error =
          case changeset.errors[:code] do
            {msg, _} -> msg
            nil -> "Failed to create shelf"
          end

        {:noreply, assign(socket, :shelf_code_error, error)}
    end
  end

  def handle_event("show_rename_shelf_modal", %{"id" => id}, socket) do
    shelf = Inventory.get_shelf!(String.to_integer(id))
    location_count = Inventory.count_locations_for_shelf(shelf)

    {:noreply,
     socket
     |> assign(:show_rename_shelf_modal, true)
     |> assign(:rename_shelf, shelf)
     |> assign(:rename_shelf_location_count, location_count)
     |> assign(:shelf_code_error, nil)}
  end

  def handle_event("close_rename_shelf_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_rename_shelf_modal, false)
     |> assign(:rename_shelf, nil)
     |> assign(:shelf_code_error, nil)}
  end

  def handle_event("rename_shelf", %{"new_code" => new_code}, socket) do
    shelf = socket.assigns.rename_shelf
    new_code = String.upcase(new_code)

    if shelf.code == new_code do
      {:noreply,
       socket
       |> assign(:show_rename_shelf_modal, false)
       |> assign(:rename_shelf, nil)}
    else
      case Inventory.rename_shelf(shelf, new_code) do
        {:ok, _shelf} ->
          {:noreply,
           socket
           |> refresh_data()
           |> assign(:show_rename_shelf_modal, false)
           |> assign(:rename_shelf, nil)
           |> assign(:shelf_code_error, nil)
           |> put_flash(:info, "Shelf renamed to #{new_code}")}

        {:error, :invalid_code} ->
          {:noreply, assign(socket, :shelf_code_error, "Invalid code format")}

        {:error, :code_exists} ->
          {:noreply, assign(socket, :shelf_code_error, "A shelf with this code already exists")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :shelf_code_error, "Failed to rename shelf")}
      end
    end
  end

  def handle_event("delete_shelf", %{"id" => id}, socket) do
    shelf = Inventory.get_shelf!(String.to_integer(id))

    case Inventory.delete_empty_shelf(shelf) do
      {:ok, _shelf} ->
        {:noreply,
         socket
         |> refresh_data()
         |> put_flash(:info, "Shelf #{shelf.code} deleted")}

      {:error, :has_items} ->
        {:noreply, put_flash(socket, :error, "Cannot delete shelf with items")}
    end
  end

  def handle_event("add_bin", %{"shelf_id" => shelf_id}, socket) do
    shelf = Inventory.get_shelf!(String.to_integer(shelf_id))

    case Inventory.add_bin_to_shelf(shelf) do
      {:ok, bin} ->
        {:noreply,
         socket
         |> refresh_data()
         |> put_flash(:info, "Bin #{bin.code} added to shelf #{shelf.code}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add bin")}
    end
  end

  def handle_event("add_cell", %{"bin_id" => bin_id}, socket) do
    bin = Inventory.get_bin!(String.to_integer(bin_id))

    case Inventory.add_cell_to_bin(bin) do
      {:ok, cell} ->
        {:noreply,
         socket
         |> refresh_data()
         |> put_flash(:info, "Cell #{cell.code} added")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add cell")}
    end
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:close_item_modal}, socket) do
    shelves = Inventory.list_shelves_with_hierarchy()
    stats = Inventory.count_locations_by_occupancy()

    {:noreply,
     socket
     |> assign(:selected_item_id, nil)
     |> assign(:shelves, shelves)
     |> assign(:stats, stats)}
  end

  def handle_info({:item_deleted, item_name}, socket) do
    shelves = Inventory.list_shelves_with_hierarchy()
    stats = Inventory.count_locations_by_occupancy()

    {:noreply,
     socket
     |> assign(:selected_item_id, nil)
     |> assign(:shelves, shelves)
     |> assign(:stats, stats)
     |> put_flash(:info, "Deleted: #{item_name}")}
  end

  def handle_info({:photo_pending, _id, photo_data}, socket) do
    send_update(ShowModal,
      id: "item-show-modal",
      pending_photo: photo_data
    )

    {:noreply, socket}
  end

  def handle_info({:photo_cleared, _id}, socket) do
    send_update(ShowModal,
      id: "item-show-modal",
      clear_pending_photo: true
    )

    {:noreply, socket}
  end

  @spec refresh_data(Socket.t()) :: Socket.t()
  defp refresh_data(socket) do
    shelves = Inventory.list_shelves_with_hierarchy()
    stats = Inventory.count_locations_by_occupancy()

    socket
    |> assign(:shelves, shelves)
    |> assign(:stats, stats)
  end
end
