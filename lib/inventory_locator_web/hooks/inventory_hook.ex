defmodule InventoryLocatorWeb.Hooks.InventoryHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Inv
  alias InventoryLocator.Marketplace
  alias Phoenix.LiveView.Socket

  @spec on_mount(atom(), map(), map(), Socket.t()) :: {:cont, Socket.t()}
  def on_mount(:default, _params, session, socket) do
    user_id = socket.assigns.current_user.id
    inventory_id = session["inventory_id"]
    admin_user? = Map.get(socket.assigns, :admin_user?, false)
    admin_mode = if admin_user?, do: session["admin_mode"] || false, else: false
    inventories = Inventory.list_accessible_inventories(user_id)

    inventory = find_inventory(inventory_id, inventories)
    inventory_role = inventory_role(user_id, inventory)
    unresolved_count = unresolved_request_count(inventory, inventory_role)

    socket =
      socket
      |> assign(:current_inventory, inventory)
      |> assign(:inventories, inventories)
      |> assign(:admin_mode, admin_mode)
      |> assign(:inventory_role, inventory_role)
      |> assign(:guest_mode, false)
      |> assign(:unresolved_request_count, unresolved_count)
      |> attach_hook(:inventory_refresh, :handle_info, &handle_inventory_refresh/2)

    {:cont, socket}
  end

  @spec find_inventory(integer() | nil, [Inv.t()]) :: Inv.t() | nil
  defp find_inventory(_id, []), do: nil
  defp find_inventory(nil, inventories), do: hd(inventories)

  defp find_inventory(inventory_id, inventories) do
    Enum.find(inventories, hd(inventories), fn inv -> inv.id == inventory_id end)
  end

  @spec inventory_role(integer(), Inv.t() | nil) :: :owner | :viewer | :none
  defp inventory_role(_user_id, nil), do: :none
  defp inventory_role(user_id, %Inv{user_id: user_id}), do: :owner
  defp inventory_role(_user_id, _inv), do: :viewer

  @spec handle_inventory_refresh(term(), Socket.t()) :: {:cont, Socket.t()} | {:halt, Socket.t()}
  defp handle_inventory_refresh({:inventory_switched, new_inventory_id}, socket) do
    user_id = socket.assigns.current_user.id

    if Inventory.user_can_access?(user_id, new_inventory_id) do
      case Inventory.get_inventory(new_inventory_id) do
        nil ->
          {:cont, socket}

        inventory ->
          role = inventory_role(user_id, inventory)

          socket =
            socket
            |> assign(:current_inventory, inventory)
            |> assign(:inventory_role, role)

          {:halt, socket}
      end
    else
      {:cont, socket}
    end
  end

  defp handle_inventory_refresh(_message, socket), do: {:cont, socket}

  @spec unresolved_request_count(Inv.t() | nil, :owner | :viewer | :none) :: non_neg_integer()
  defp unresolved_request_count(nil, _role), do: 0
  defp unresolved_request_count(_inventory, :none), do: 0

  defp unresolved_request_count(inventory, :owner) do
    Marketplace.count_unresolved_requests(inventory.id)
  end

  defp unresolved_request_count(_inventory, _role), do: 0
end
