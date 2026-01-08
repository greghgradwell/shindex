defmodule InventoryLocatorWeb.ItemLive.Show do
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.{ItemType, Location}

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"id" => id}, _session, socket) do
    item = Inventory.get_item_type_with_location!(String.to_integer(id))

    {:ok,
     socket
     |> assign(:item, item)
     |> assign(:page_title, item.name)
     |> assign(:show_restore_modal, false)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("increment_quantity", _params, socket) do
    item = socket.assigns.item
    new_quantity = item.quantity + 1

    case Inventory.update_item_type(item, %{quantity: new_quantity}) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> put_flash(:info, "Quantity updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update quantity")}
    end
  end

  def handle_event("decrement_quantity", _params, socket) do
    item = socket.assigns.item

    if item.quantity > 0 do
      new_quantity = item.quantity - 1

      case Inventory.update_item_type(item, %{quantity: new_quantity}) do
        {:ok, updated_item} ->
          updated_item = Inventory.get_item_type_with_location!(updated_item.id)

          {:noreply,
           socket
           |> assign(:item, updated_item)
           |> put_flash(:info, "Quantity updated")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update quantity")}
      end
    else
      {:noreply, socket}
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
    {:noreply, assign(socket, :show_restore_modal, false)}
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

  @spec do_restore(Phoenix.LiveView.Socket.t(), ItemType.t(), Location.t(), integer(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_restore(socket, item, location, quantity, location_code) do
    case Inventory.restore_item_type(item, %{location_id: location.id, quantity: quantity}) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> assign(:show_restore_modal, false)
         |> assign(:location_warning, nil)
         |> put_flash(:info, "Item restored to location #{location_code}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to restore item")}
    end
  end
end
