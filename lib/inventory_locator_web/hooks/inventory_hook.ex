defmodule InventoryLocatorWeb.Hooks.InventoryHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  @spec on_mount(atom(), map(), map(), Socket.t()) :: {:cont, Socket.t()}
  def on_mount(:default, _params, session, socket) do
    inventory_id = session["inventory_id"]
    admin_user? = Map.get(socket.assigns, :admin_user?, false)
    admin_mode = if admin_user?, do: session["admin_mode"] || false, else: false
    inventories = Inventory.list_inventories()

    inventory = find_inventory(inventory_id, inventories)

    socket =
      socket
      |> assign(:current_inventory, inventory)
      |> assign(:inventories, inventories)
      |> assign(:admin_mode, admin_mode)
      |> attach_hook(:inventory_refresh, :handle_info, &handle_inventory_refresh/2)

    {:cont, socket}
  end

  @spec find_inventory(integer() | nil, [Inventory.Inv.t()]) :: Inventory.Inv.t()
  defp find_inventory(nil, inventories), do: hd(inventories)

  defp find_inventory(inventory_id, inventories) do
    Enum.find(inventories, hd(inventories), fn inv -> inv.id == inventory_id end)
  end

  @spec handle_inventory_refresh(term(), Socket.t()) :: {:cont, Socket.t()} | {:halt, Socket.t()}
  defp handle_inventory_refresh({:inventory_switched, new_inventory_id}, socket) do
    case Inventory.get_inventory(new_inventory_id) do
      nil ->
        {:cont, socket}

      inventory ->
        socket = assign(socket, :current_inventory, inventory)
        {:halt, socket}
    end
  end

  defp handle_inventory_refresh(_message, socket), do: {:cont, socket}
end
