defmodule InventoryLocatorWeb.InventoryLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.AuthHelpers

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Inv
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Inventories")
     |> assign(:inventories_with_counts, Inventory.list_inventories_with_counts())
     |> assign(:show_create_modal, false)
     |> assign(:name_error, nil)
     |> assign(:show_edit_modal, false)
     |> assign(:edit_inventory, nil)
     |> assign(:show_delete_modal, false)
     |> assign(:delete_inventory, nil)
     |> assign(:delete_shelf_count, 0)
     |> assign(:delete_item_count, 0)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("show_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:name_error, nil)}
  end

  def handle_event("close_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign(:name_error, nil)}
  end

  def handle_event("validate_name", %{"name" => name}, socket) do
    error = validate_name(name)
    {:noreply, assign(socket, :name_error, error)}
  end

  def handle_event("create_inventory", %{"name" => name, "description" => description}, socket) do
    require_admin(socket, fn socket ->
      attrs = %{name: String.trim(name), description: nullify_blank(description)}

      case Inventory.create_inventory(attrs) do
        {:ok, _inv} ->
          {:noreply,
           socket
           |> assign(:inventories_with_counts, Inventory.list_inventories_with_counts())
           |> assign(:show_create_modal, false)
           |> assign(:name_error, nil)
           |> put_flash(:info, "Inventory created: #{attrs.name}")}

        {:error, changeset} ->
          error = extract_name_error(changeset)
          {:noreply, assign(socket, :name_error, error)}
      end
    end)
  end

  def handle_event("show_edit_modal", %{"id" => id}, socket) do
    inv = Inventory.get_inventory!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:show_edit_modal, true)
     |> assign(:edit_inventory, inv)
     |> assign(:name_error, nil)}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:edit_inventory, nil)
     |> assign(:name_error, nil)}
  end

  def handle_event("update_inventory", %{"name" => name, "description" => description}, socket) do
    require_admin(socket, fn socket ->
      inv = socket.assigns.edit_inventory
      attrs = %{name: String.trim(name), description: nullify_blank(description)}

      case Inventory.update_inventory(inv, attrs) do
        {:ok, _inv} ->
          {:noreply,
           socket
           |> assign(:inventories_with_counts, Inventory.list_inventories_with_counts())
           |> assign(:show_edit_modal, false)
           |> assign(:edit_inventory, nil)
           |> assign(:name_error, nil)
           |> put_flash(:info, "Inventory updated: #{attrs.name}")}

        {:error, changeset} ->
          error = extract_name_error(changeset)
          {:noreply, assign(socket, :name_error, error)}
      end
    end)
  end

  def handle_event("show_delete_modal", %{"id" => id, "shelves" => shelves, "items" => items}, socket) do
    inv = Inventory.get_inventory!(String.to_integer(id))
    shelf_count = String.to_integer(shelves)
    item_count = String.to_integer(items)

    {:noreply,
     socket
     |> assign(:show_delete_modal, true)
     |> assign(:delete_inventory, inv)
     |> assign(:delete_shelf_count, shelf_count)
     |> assign(:delete_item_count, item_count)
     |> assign(:delete_confirmation, "")}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:delete_inventory, nil)
     |> assign(:delete_confirmation, "")}
  end

  def handle_event("validate_delete", %{"confirmation" => confirmation}, socket) do
    {:noreply, assign(socket, :delete_confirmation, confirmation)}
  end

  def handle_event("delete_inventory", _params, socket) do
    require_admin(socket, fn socket ->
      inv = socket.assigns.delete_inventory
      confirmation = socket.assigns.delete_confirmation

      if confirmation == inv.name do
        case Inventory.delete_inventory(inv) do
          {:ok, _inv} ->
            {:noreply,
             socket
             |> assign(:inventories_with_counts, Inventory.list_inventories_with_counts())
             |> assign(:show_delete_modal, false)
             |> assign(:delete_inventory, nil)
             |> assign(:delete_confirmation, "")
             |> put_flash(:info, "Deleted inventory: #{inv.name}")}

          {:error, :last_inventory} ->
            {:noreply, put_flash(socket, :error, "Cannot delete the last inventory")}
        end
      else
        {:noreply, put_flash(socket, :error, "Confirmation does not match inventory name")}
      end
    end)
  end

  @spec validate_name(String.t()) :: String.t() | nil
  defp validate_name(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> nil
      String.length(trimmed) > 50 -> "Name must be 50 characters or less"
      true -> nil
    end
  end

  @spec extract_name_error(Ecto.Changeset.t()) :: String.t()
  defp extract_name_error(changeset) do
    case changeset.errors[:name] do
      {msg, _} -> msg
      nil -> "Failed to save inventory"
    end
  end

  @spec nullify_blank(String.t()) :: String.t() | nil
  defp nullify_blank(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @spec current_inventory?(Inv.t(), Inv.t()) :: boolean()
  def current_inventory?(%Inv{} = inv, %Inv{} = current) do
    inv.id == current.id
  end
end
