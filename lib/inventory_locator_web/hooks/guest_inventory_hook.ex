defmodule InventoryLocatorWeb.Hooks.GuestInventoryHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  @spec on_mount(atom(), map(), map(), Socket.t()) :: {:cont, Socket.t()} | {:halt, Socket.t()}
  def on_mount(:default, %{"code" => code}, _session, socket) do
    case Inventory.resolve_public_code(code) do
      {:ok, inventory} ->
        socket =
          socket
          |> assign(:current_user, nil)
          |> assign(:admin_user?, false)
          |> assign(:admin_mode, false)
          |> assign(:current_inventory, inventory)
          |> assign(:inventories, [inventory])
          |> assign(:inventory_role, :guest)
          |> assign(:unresolved_request_count, 0)
          |> assign(:guest_mode, true)

        {:cont, socket}

      :invalid ->
        socket = redirect(socket, to: "/landing")
        {:halt, socket}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    socket = redirect(socket, to: "/landing")
    {:halt, socket}
  end
end
