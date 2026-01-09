defmodule InventoryLocatorWeb.ItemLive.ShowModal do
  @moduledoc false
  use InventoryLocatorWeb, :live_component

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Inventory.Location
  alias Phoenix.LiveView.Socket

  @impl true
  @spec update(map(), Socket.t()) :: {:ok, Socket.t()}
  def update(%{item_id: item_id} = assigns, socket) do
    item = Inventory.get_item_type_with_location!(item_id)
    location_codes = Inventory.list_location_codes()
    project_names = Inventory.list_project_names()
    installations = Inventory.list_installations_for_item(item)
    installed_quantity = Enum.sum(Enum.map(installations, & &1.quantity))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:item, item)
     |> assign(:show_restore_modal, false)
     |> assign(:show_archive_quantity_modal, false)
     |> assign(:editing, false)
     |> assign(:moving, false)
     |> assign(:installing, false)
     |> assign(:edit_changeset, nil)
     |> assign(:location_codes, location_codes)
     |> assign(:project_names, project_names)
     |> assign(:installations, installations)
     |> assign(:installed_quantity, installed_quantity)
     |> assign(:pending_restore_quantity, nil)
     |> assign(:location_warning, nil)
     |> assign(:move_location_warning, nil)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_item_modal})
    {:noreply, socket}
  end

  def handle_event("increment_quantity", _params, socket) do
    item = socket.assigns.item
    new_quantity = item.quantity + 1

    case Inventory.update_item_type(item, %{quantity: new_quantity}) do
      {:ok, _updated_item} ->
        {:noreply,
         socket
         |> refresh_item_data()
         |> put_flash(:info, "Quantity updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update quantity")}
    end
  end

  def handle_event("decrement_quantity", _params, socket) do
    item = socket.assigns.item
    new_quantity = item.quantity - 1

    cond do
      new_quantity < 0 ->
        {:noreply, socket}

      new_quantity == 0 ->
        {:noreply, assign(socket, :show_archive_quantity_modal, true)}

      true ->
        case Inventory.update_item_type(item, %{quantity: new_quantity}) do
          {:ok, _updated_item} ->
            {:noreply,
             socket
             |> refresh_item_data()
             |> put_flash(:info, "Quantity updated")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to update quantity")}
        end
    end
  end

  def handle_event("archive", _params, socket) do
    item = socket.assigns.item

    case Inventory.archive_item_type(item) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> put_flash(:info, "Item archived. Location is now available for reuse.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to archive item")}
    end
  end

  def handle_event("show_restore_modal", _params, socket) do
    {:noreply, assign(socket, :show_restore_modal, true)}
  end

  def handle_event("close_restore_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_restore_modal, false)
     |> assign(:pending_restore_quantity, nil)}
  end

  def handle_event("confirm_archive_from_quantity", _params, socket) do
    item = socket.assigns.item

    case Inventory.archive_item_type(item) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> assign(:show_archive_quantity_modal, false)
         |> put_flash(:info, "Item archived. Location is now available for reuse.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:show_archive_quantity_modal, false)
         |> put_flash(:error, "Failed to archive item")}
    end
  end

  def handle_event("cancel_archive_from_quantity", _params, socket) do
    {:noreply, assign(socket, :show_archive_quantity_modal, false)}
  end

  def handle_event("restore", %{"location_code" => location_code, "quantity" => qty_str}, socket) do
    item = socket.assigns.item
    quantity = String.to_integer(qty_str)

    case Inventory.ensure_location_with_code(location_code) do
      {:ok, location} ->
        do_restore(socket, item, location, quantity, location_code)

      {:ok, location, _item_count} ->
        do_restore(socket, item, location, quantity, location_code)

      {:error, :invalid_format} ->
        {:noreply, put_flash(socket, :error, "Invalid location code format")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to restore item")}
    end
  end

  def handle_event("validate_location", %{"location_code" => code}, socket) do
    case Inventory.ensure_location_with_code(code) do
      {:ok, _location, item_count} when item_count > 0 ->
        {:noreply, assign(socket, :location_warning, %{code: code, count: item_count})}

      _ ->
        {:noreply, assign(socket, :location_warning, nil)}
    end
  end

  def handle_event("update_quantity", %{"quantity" => qty_str}, socket) do
    item = socket.assigns.item

    case Integer.parse(qty_str) do
      {0, _} ->
        {:noreply, assign(socket, :show_archive_quantity_modal, true)}

      {quantity, _} when quantity > 0 ->
        case Inventory.update_item_type(item, %{quantity: quantity}) do
          {:ok, _updated_item} ->
            {:noreply,
             socket
             |> refresh_item_data()
             |> put_flash(:info, "Quantity updated")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to update quantity")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid quantity")}
    end
  end

  def handle_event("toggle_edit", _params, socket) do
    item = socket.assigns.item
    changeset = ItemType.changeset(item, %{})

    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:edit_changeset, changeset)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, false)
     |> assign(:edit_changeset, nil)}
  end

  def handle_event("update_item_details", params, socket) do
    item = socket.assigns.item

    attrs = %{
      name: Map.get(params, "name", item.name),
      manufacturer: Map.get(params, "manufacturer", ""),
      model: Map.get(params, "model", ""),
      description: Map.get(params, "description", "")
    }

    case Inventory.update_item_type(item, attrs) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> assign(:editing, false)
         |> assign(:edit_changeset, nil)
         |> put_flash(:info, "Item details updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update item details")}
    end
  end

  def handle_event("toggle_move", _params, socket) do
    {:noreply, assign(socket, :moving, true)}
  end

  def handle_event("cancel_move", _params, socket) do
    {:noreply,
     socket
     |> assign(:moving, false)
     |> assign(:move_location_warning, nil)}
  end

  def handle_event("validate_move_location", %{"location_code" => code}, socket) do
    case Inventory.ensure_location_with_code(code) do
      {:ok, _location, item_count} when item_count > 0 ->
        {:noreply, assign(socket, :move_location_warning, %{code: code, count: item_count})}

      _ ->
        {:noreply, assign(socket, :move_location_warning, nil)}
    end
  end

  def handle_event("move_to_location", %{"location_code" => location_code}, socket) do
    item = socket.assigns.item

    case Inventory.ensure_location_with_code(location_code) do
      {:ok, location} ->
        do_move(socket, item, location, location_code)

      {:ok, location, _item_count} ->
        do_move(socket, item, location, location_code)

      {:error, :invalid_format} ->
        {:noreply, put_flash(socket, :error, "Invalid location code format")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to move item")}
    end
  end

  def handle_event("ghost_value_changed", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_install", _params, socket) do
    {:noreply, assign(socket, :installing, true)}
  end

  def handle_event("cancel_install", _params, socket) do
    {:noreply, assign(socket, :installing, false)}
  end

  def handle_event("install_item", %{"project_name" => project_name, "quantity" => qty_str}, socket) do
    item = socket.assigns.item

    case Integer.parse(qty_str) do
      {quantity, _} when quantity > 0 ->
        case Inventory.install_item(item, project_name, quantity) do
          {:ok, _installation, updated_item} ->
            message =
              if updated_item.archived do
                "Installed #{quantity} in #{String.upcase(project_name)}. Item archived (none left in stock)."
              else
                "Installed #{quantity} in #{String.upcase(project_name)}"
              end

            {:noreply,
             socket
             |> refresh_item_data()
             |> assign(:installing, false)
             |> put_flash(:info, message)}

          {:error, :insufficient_quantity} ->
            {:noreply, put_flash(socket, :error, "Not enough in stock")}

          {:error, :archived} ->
            {:noreply, put_flash(socket, :error, "Cannot install from archived item")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to install item")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid quantity")}
    end
  end

  def handle_event("increment_installation", %{"installation_id" => id_str}, socket) do
    installation_id = String.to_integer(id_str)
    installation = Enum.find(socket.assigns.installations, &(&1.id == installation_id))
    item = socket.assigns.item

    cond do
      is_nil(installation) ->
        {:noreply, put_flash(socket, :error, "Installation not found")}

      item.archived ->
        {:noreply, put_flash(socket, :error, "Cannot add to archived item")}

      item.quantity < 1 ->
        {:noreply, put_flash(socket, :error, "No stock available")}

      true ->
        case Inventory.install_item(item, installation.project_name, 1) do
          {:ok, _installation, _updated_item} ->
            {:noreply,
             socket
             |> refresh_item_data()
             |> put_flash(:info, "Added 1 to #{installation.project_name}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to add to installation")}
        end
    end
  end

  def handle_event("decrement_installation", %{"installation_id" => id_str}, socket) do
    do_uninstall(socket, id_str, 1)
  end

  def handle_event("uninstall_item", %{"installation_id" => id_str}, socket) do
    installation_id = String.to_integer(id_str)
    installation = Enum.find(socket.assigns.installations, &(&1.id == installation_id))

    if installation do
      do_uninstall(socket, id_str, installation.quantity)
    else
      {:noreply, put_flash(socket, :error, "Installation not found")}
    end
  end

  @spec do_uninstall(Socket.t(), String.t(), pos_integer()) :: {:noreply, Socket.t()}
  defp do_uninstall(socket, id_str, quantity) do
    installation_id = String.to_integer(id_str)
    installation = Enum.find(socket.assigns.installations, &(&1.id == installation_id))

    if installation do
      case Inventory.uninstall_item(installation, quantity) do
        {:ok, :returned_to_stock, _updated_item} ->
          {:noreply,
           socket
           |> refresh_item_data()
           |> put_flash(:info, "Returned #{quantity} to stock from #{installation.project_name}")}

        {:ok, :needs_restore, restore_quantity} ->
          {:noreply,
           socket
           |> assign(:pending_restore_quantity, restore_quantity)
           |> assign(:show_restore_modal, true)
           |> refresh_item_data()
           |> put_flash(
             :info,
             "#{restore_quantity} removed from #{installation.project_name}. Choose a location to restore."
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove installation")}
      end
    else
      {:noreply, put_flash(socket, :error, "Installation not found")}
    end
  end

  @spec refresh_item_data(Socket.t()) :: Socket.t()
  defp refresh_item_data(socket) do
    item = Inventory.get_item_type_with_location!(socket.assigns.item.id)
    installations = Inventory.list_installations_for_item(item)
    installed_quantity = Enum.sum(Enum.map(installations, & &1.quantity))
    project_names = Inventory.list_project_names()

    socket
    |> assign(:item, item)
    |> assign(:installations, installations)
    |> assign(:installed_quantity, installed_quantity)
    |> assign(:project_names, project_names)
  end

  @spec do_move(Socket.t(), ItemType.t(), Location.t(), String.t()) ::
          {:noreply, Socket.t()}
  defp do_move(socket, item, location, location_code) do
    case Inventory.update_item_type(item, %{location_id: location.id}) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> assign(:moving, false)
         |> assign(:move_location_warning, nil)
         |> put_flash(:info, "Item moved to location #{location_code}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to move item")}
    end
  end

  @spec do_restore(Socket.t(), ItemType.t(), Location.t(), integer(), String.t()) ::
          {:noreply, Socket.t()}
  defp do_restore(socket, item, location, quantity, location_code) do
    case Inventory.restore_item_type(item, %{location_id: location.id, quantity: quantity}) do
      {:ok, _updated_item} ->
        {:noreply,
         socket
         |> refresh_item_data()
         |> assign(:show_restore_modal, false)
         |> assign(:location_warning, nil)
         |> assign(:pending_restore_quantity, nil)
         |> put_flash(:info, "Item restored to location #{location_code}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to restore item")}
    end
  end
end
