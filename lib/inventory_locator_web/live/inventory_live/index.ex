defmodule InventoryLocatorWeb.InventoryLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Inv
  alias InventoryLocator.Inventory.InventoryShareCode
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id

    {:ok,
     socket
     |> assign(:page_title, "Inventories")
     |> assign(:inventories_with_counts, Inventory.list_accessible_inventories_with_counts(user_id))
     |> assign(:show_create_modal, false)
     |> assign(:name_error, nil)
     |> assign(:show_edit_modal, false)
     |> assign(:edit_inventory, nil)
     |> assign(:show_delete_modal, false)
     |> assign(:delete_inventory, nil)
     |> assign(:delete_shelf_count, 0)
     |> assign(:delete_item_count, 0)
     |> assign(:delete_confirmation, "")
     |> assign(:show_share_modal, false)
     |> assign(:share_inventory, nil)
     |> assign(:share_codes, [])
     |> assign(:friends, [])
     |> assign(:new_share_code, nil)
     |> assign(:public_link, nil)}
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
    user_id = socket.assigns.current_user.id
    attrs = %{name: String.trim(name), description: nullify_blank(description), user_id: user_id}

    case Inventory.create_inventory(attrs) do
      {:ok, _inv} ->
        {:noreply,
         socket
         |> assign(:inventories_with_counts, Inventory.list_accessible_inventories_with_counts(user_id))
         |> assign(:show_create_modal, false)
         |> assign(:name_error, nil)
         |> put_flash(:info, "Inventory created: #{attrs.name}")}

      {:error, changeset} ->
        error = extract_name_error(changeset)
        {:noreply, assign(socket, :name_error, error)}
    end
  end

  def handle_event("show_edit_modal", %{"id" => id}, socket) do
    inv = Inventory.get_inventory!(String.to_integer(id))

    require_inventory_owner(socket, inv, fn socket ->
      {:noreply,
       socket
       |> assign(:show_edit_modal, true)
       |> assign(:edit_inventory, inv)
       |> assign(:name_error, nil)}
    end)
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:edit_inventory, nil)
     |> assign(:name_error, nil)}
  end

  def handle_event("update_inventory", %{"name" => name, "description" => description}, socket) do
    require_inventory_owner(socket, socket.assigns.edit_inventory, fn socket ->
      user_id = socket.assigns.current_user.id
      inv = socket.assigns.edit_inventory
      attrs = %{name: String.trim(name), description: nullify_blank(description)}

      case Inventory.update_inventory(inv, attrs) do
        {:ok, _inv} ->
          {:noreply,
           socket
           |> assign(:inventories_with_counts, Inventory.list_accessible_inventories_with_counts(user_id))
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

    require_inventory_owner(socket, inv, fn socket ->
      shelf_count = String.to_integer(shelves)
      item_count = String.to_integer(items)

      {:noreply,
       socket
       |> assign(:show_delete_modal, true)
       |> assign(:delete_inventory, inv)
       |> assign(:delete_shelf_count, shelf_count)
       |> assign(:delete_item_count, item_count)
       |> assign(:delete_confirmation, "")}
    end)
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
    require_inventory_owner(socket, socket.assigns.delete_inventory, fn socket ->
      user_id = socket.assigns.current_user.id
      inv = socket.assigns.delete_inventory
      confirmation = socket.assigns.delete_confirmation

      if confirmation == inv.name do
        case Inventory.delete_inventory(inv) do
          {:ok, _inv} ->
            {:noreply,
             socket
             |> assign(:inventories_with_counts, Inventory.list_accessible_inventories_with_counts(user_id))
             |> assign(:show_delete_modal, false)
             |> assign(:delete_inventory, nil)
             |> assign(:delete_confirmation, "")
             |> put_flash(:info, "Deleted inventory: #{inv.name}")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to delete inventory")}
        end
      else
        {:noreply, put_flash(socket, :error, "Confirmation does not match inventory name")}
      end
    end)
  end

  def handle_event("show_share_modal", %{"id" => id}, socket) do
    inv = Inventory.get_inventory!(String.to_integer(id))

    require_inventory_owner(socket, inv, fn socket ->
      share_codes = Inventory.list_share_codes(inv.id)
      friends = Inventory.list_friends(inv.id)
      public_link = Inventory.get_public_link(inv.id)

      {:noreply,
       socket
       |> assign(:show_share_modal, true)
       |> assign(:share_inventory, inv)
       |> assign(:share_codes, share_codes)
       |> assign(:friends, friends)
       |> assign(:new_share_code, nil)
       |> assign(:public_link, public_link)}
    end)
  end

  def handle_event("close_share_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_share_modal, false)
     |> assign(:share_inventory, nil)
     |> assign(:share_codes, [])
     |> assign(:friends, [])
     |> assign(:new_share_code, nil)
     |> assign(:public_link, nil)}
  end

  def handle_event("generate_share_code", _params, socket) do
    require_inventory_owner(socket, socket.assigns.share_inventory, fn socket ->
      inv = socket.assigns.share_inventory
      user_id = socket.assigns.current_user.id

      case Inventory.create_share_code(inv.id, user_id) do
        {:ok, share_code} ->
          share_codes = Inventory.list_share_codes(inv.id)

          {:noreply,
           socket
           |> assign(:share_codes, share_codes)
           |> assign(:new_share_code, share_code.code)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to generate share code")}
      end
    end)
  end

  def handle_event("generate_public_link", _params, socket) do
    require_inventory_owner(socket, socket.assigns.share_inventory, fn socket ->
      inv = socket.assigns.share_inventory
      user_id = socket.assigns.current_user.id

      case Inventory.create_public_link(inv.id, user_id) do
        {:ok, public_link} ->
          {:noreply, assign(socket, :public_link, public_link)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to generate public link")}
      end
    end)
  end

  def handle_event("revoke_public_link", _params, socket) do
    require_inventory_owner(socket, socket.assigns.share_inventory, fn socket ->
      case socket.assigns.public_link do
        %{id: id} ->
          case Inventory.revoke_public_link(id) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:public_link, nil)
               |> put_flash(:info, "Public link revoked")}

            {:error, :not_found} ->
              {:noreply, put_flash(socket, :error, "Public link not found")}
          end

        nil ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("remove_friend", %{"user-id" => friend_user_id_str}, socket) do
    require_inventory_owner(socket, socket.assigns.share_inventory, fn socket ->
      inv = socket.assigns.share_inventory
      friend_user_id = String.to_integer(friend_user_id_str)

      case Inventory.remove_friend(inv.id, friend_user_id) do
        {:ok, _friend} ->
          user_id = socket.assigns.current_user.id
          friends = Inventory.list_friends(inv.id)

          {:noreply,
           socket
           |> assign(:friends, friends)
           |> assign(:inventories_with_counts, Inventory.list_accessible_inventories_with_counts(user_id))
           |> put_flash(:info, "Friend removed")}

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "Friend not found")}
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

  @spec current_inventory?(Inv.t(), Inv.t() | nil) :: boolean()
  def current_inventory?(_inv, nil), do: false

  def current_inventory?(%Inv{} = inv, %Inv{} = current) do
    inv.id == current.id
  end

  @spec owned?(Inv.t() | nil, integer()) :: boolean()
  def owned?(nil, _user_id), do: false
  def owned?(%Inv{user_id: user_id}, user_id), do: true
  def owned?(_inv, _user_id), do: false

  @spec require_inventory_owner(Socket.t(), Inv.t() | nil, (Socket.t() -> {:noreply, Socket.t()})) ::
          {:noreply, Socket.t()}
  defp require_inventory_owner(socket, inv, func) do
    if owned?(inv, socket.assigns.current_user.id) do
      func.(socket)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to modify this inventory.")}
    end
  end

  @spec share_code_status(InventoryShareCode.t()) :: String.t()
  def share_code_status(share_code) do
    cond do
      not is_nil(share_code.used_at) -> "Used"
      not InventoryShareCode.valid?(share_code) -> "Expired"
      true -> "Active"
    end
  end

  @spec share_url(String.t()) :: String.t()
  def share_url(code) do
    InventoryLocatorWeb.Endpoint.url() <> "/share/" <> code
  end

  @spec public_link_url(String.t()) :: String.t()
  def public_link_url(code) do
    InventoryLocatorWeb.Endpoint.url() <> "/view/" <> code
  end
end
