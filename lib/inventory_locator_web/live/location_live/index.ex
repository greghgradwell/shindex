defmodule InventoryLocatorWeb.LocationLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.AuthHelpers
  import InventoryLocatorWeb.LocationLive.Components

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Shelf
  alias InventoryLocatorWeb.ItemLive.ShowModal
  alias Phoenix.LiveView.Socket

  require Logger

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    inventory_id = socket.assigns.current_inventory.id
    shelves = Inventory.list_shelves_with_hierarchy(inventory_id)
    stats = Inventory.count_locations_by_occupancy(inventory_id)

    {:ok,
     socket
     |> assign(:shelves, shelves)
     |> assign(:stats, stats)
     |> assign(:page_title, "Location Management")
     |> assign(:selected_item_id, nil)
     |> assign(:start_editing, false)
     |> assign(:shelf_filter, MapSet.new())
     |> assign(:show_create_shelf_modal, false)
     |> assign(:show_rename_shelf_modal, false)
     |> assign(:rename_shelf, nil)
     |> assign(:rename_shelf_location_count, 0)
     |> assign(:shelf_code_error, nil)
     |> assign(:show_rename_bin_modal, false)
     |> assign(:rename_bin, nil)
     |> assign(:rename_bin_shelf, nil)
     |> assign(:all_shelves, [])
     |> assign(:bin_code_error, nil)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("delete_location", %{"id" => id}, socket) when is_integer(id) do
    require_owner(socket, fn socket ->
      inventory_id = socket.assigns.current_inventory.id

      case Inventory.delete_empty_location(id) do
        {:ok, _location} ->
          shelves = Inventory.list_shelves_with_hierarchy(inventory_id)
          stats = Inventory.count_locations_by_occupancy(inventory_id)

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
    end)
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("clear_shelf_filter", _params, socket) do
    {:noreply, assign(socket, :shelf_filter, MapSet.new())}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("toggle_shelf_filter", %{"prefix" => prefix}, socket) do
    filter = socket.assigns.shelf_filter

    updated =
      if MapSet.member?(filter, prefix) do
        MapSet.delete(filter, prefix)
      else
        MapSet.put(filter, prefix)
      end

    {:noreply, assign(socket, :shelf_filter, updated)}
  end

  def handle_event("open_item_modal", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_item_id, String.to_integer(id))}
  end

  def handle_event("show_add_item_modal", %{"location_code" => location_code}, socket) do
    require_owner(socket, fn socket ->
      inventory_id = socket.assigns.current_inventory.id

      case Inventory.create_item_with_location(%{
             inventory_id: inventory_id,
             location_code: location_code,
             name: "New Item"
           }) do
        {:ok, item} ->
          {:noreply,
           socket
           |> assign(:selected_item_id, item.id)
           |> assign(:start_editing, true)}

        {:error, reason} ->
          Logger.warning("Failed to create item at #{location_code}: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to create item")}
      end
    end)
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
    require_owner(socket, fn socket ->
      bin_count = String.to_integer(bin_count_str)
      shelf_code = String.upcase(code)
      inventory_id = socket.assigns.current_inventory.id

      case Inventory.create_shelf_with_bins(inventory_id, %{code: shelf_code}, bin_count) do
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
    end)
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
    require_owner(socket, fn socket ->
      shelf = socket.assigns.rename_shelf
      new_code = String.upcase(new_code)
      inventory_id = socket.assigns.current_inventory.id

      if shelf.code == new_code do
        {:noreply,
         socket
         |> assign(:show_rename_shelf_modal, false)
         |> assign(:rename_shelf, nil)}
      else
        case Inventory.rename_shelf(inventory_id, shelf, new_code) do
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
    end)
  end

  def handle_event("delete_shelf", %{"id" => id}, socket) do
    require_owner(socket, fn socket ->
      shelf = Inventory.get_shelf!(String.to_integer(id))

      case Inventory.delete_empty_shelf(shelf) do
        {:ok, _shelf} ->
          {:noreply,
           socket
           |> refresh_data()
           |> put_flash(:info, "Shelf #{shelf.code} deleted")}

        {:error, :system_shelf} ->
          {:noreply, put_flash(socket, :error, "Cannot delete system shelves")}

        {:error, :has_items} ->
          {:noreply, put_flash(socket, :error, "Cannot delete shelf with items")}
      end
    end)
  end

  def handle_event("add_bin", %{"shelf_id" => shelf_id}, socket) do
    require_owner(socket, fn socket ->
      shelf = Inventory.get_shelf!(String.to_integer(shelf_id))

      case Inventory.add_bin_to_shelf(shelf) do
        {:ok, bin} ->
          {:noreply,
           socket
           |> refresh_data()
           |> put_flash(:info, "Bin #{bin.code} added to shelf #{shelf.code}")}

        {:error, :system_shelf} ->
          {:noreply, put_flash(socket, :error, "Cannot modify system shelves")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to add bin")}
      end
    end)
  end

  def handle_event("show_rename_bin_modal", %{"id" => id, "shelf_id" => shelf_id}, socket) do
    inventory_id = socket.assigns.current_inventory.id
    bin = Inventory.get_bin!(String.to_integer(id))
    shelf = Inventory.get_shelf!(String.to_integer(shelf_id))
    all_shelves = Inventory.list_shelves(inventory_id)

    {:noreply,
     socket
     |> assign(:show_rename_bin_modal, true)
     |> assign(:rename_bin, bin)
     |> assign(:rename_bin_shelf, shelf)
     |> assign(:all_shelves, all_shelves)
     |> assign(:bin_code_error, nil)}
  end

  def handle_event("close_rename_bin_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_rename_bin_modal, false)
     |> assign(:rename_bin, nil)
     |> assign(:rename_bin_shelf, nil)
     |> assign(:all_shelves, [])
     |> assign(:bin_code_error, nil)}
  end

  def handle_event("validate_bin_move", %{"new_code" => code}, socket) do
    error =
      cond do
        code == "" ->
          nil

        not Bin.valid_code?(code) ->
          "Must be a number between #{Bin.min_code()} and #{Bin.max_code()}"

        true ->
          nil
      end

    {:noreply, assign(socket, :bin_code_error, error)}
  end

  def handle_event("move_bin", %{"new_code" => new_code, "target_shelf_id" => target_shelf_id_str}, socket) do
    require_owner(socket, fn socket ->
      bin = socket.assigns.rename_bin
      source_shelf = socket.assigns.rename_bin_shelf
      target_shelf_id = String.to_integer(target_shelf_id_str)
      target_shelf = Inventory.get_shelf!(target_shelf_id)

      same_location = bin.code == new_code and source_shelf.id == target_shelf_id

      if same_location do
        {:noreply,
         socket
         |> assign(:show_rename_bin_modal, false)
         |> assign(:rename_bin, nil)
         |> assign(:rename_bin_shelf, nil)
         |> assign(:all_shelves, [])}
      else
        case Inventory.move_bin(bin, target_shelf, new_code) do
          {:ok, _bin} ->
            new_location = "#{target_shelf.code}-#{new_code}"

            {:noreply,
             socket
             |> refresh_data()
             |> assign(:show_rename_bin_modal, false)
             |> assign(:rename_bin, nil)
             |> assign(:rename_bin_shelf, nil)
             |> assign(:all_shelves, [])
             |> assign(:bin_code_error, nil)
             |> put_flash(:info, "Bin moved to #{new_location}")}

          {:error, :invalid_code} ->
            {:noreply,
             assign(socket, :bin_code_error, "Must be a number between #{Bin.min_code()} and #{Bin.max_code()}")}

          {:error, :code_exists} ->
            {:noreply, assign(socket, :bin_code_error, "A bin already exists at #{target_shelf.code}-#{new_code}")}

          {:error, _changeset} ->
            {:noreply, assign(socket, :bin_code_error, "Failed to move bin")}
        end
      end
    end)
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:close_item_modal}, socket) do
    inventory_id = socket.assigns.current_inventory.id
    shelves = Inventory.list_shelves_with_hierarchy(inventory_id)
    stats = Inventory.count_locations_by_occupancy(inventory_id)

    {:noreply,
     socket
     |> assign(:selected_item_id, nil)
     |> assign(:start_editing, false)
     |> assign(:shelves, shelves)
     |> assign(:stats, stats)}
  end

  def handle_info({:item_deleted, item_name}, socket) do
    inventory_id = socket.assigns.current_inventory.id
    shelves = Inventory.list_shelves_with_hierarchy(inventory_id)
    stats = Inventory.count_locations_by_occupancy(inventory_id)

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

  @impl true
  @spec handle_info({:flash, atom(), String.t()}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:flash, kind, message}, socket) do
    Process.send_after(self(), {:clear_flash, kind}, 2000)
    {:noreply, put_flash(socket, kind, message)}
  end

  @impl true
  @spec handle_info({:clear_flash, atom()}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:clear_flash, kind}, socket) do
    {:noreply, clear_flash(socket, kind)}
  end

  @spec refresh_data(Socket.t()) :: Socket.t()
  defp refresh_data(socket) do
    inventory_id = socket.assigns.current_inventory.id
    shelves = Inventory.list_shelves_with_hierarchy(inventory_id)
    stats = Inventory.count_locations_by_occupancy(inventory_id)

    socket
    |> assign(:shelves, shelves)
    |> assign(:stats, stats)
  end
end
