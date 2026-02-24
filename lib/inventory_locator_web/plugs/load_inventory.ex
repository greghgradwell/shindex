defmodule InventoryLocatorWeb.Plugs.LoadInventory do
  @moduledoc false
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  import Plug.Conn

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Inv
  alias InventoryLocator.Marketplace

  @bypass_paths ["/inventories", "/share/"]

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    user_id = conn.assigns.current_user.id
    inventory_id = get_session(conn, :inventory_id)
    inventories = Inventory.list_accessible_inventories(user_id)

    case inventories do
      [] ->
        if bypass_path?(conn.request_path) do
          conn
          |> assign(:current_inventory, nil)
          |> assign(:inventories, [])
          |> assign(:admin_mode, false)
          |> assign(:inventory_role, :none)
        else
          conn
          |> put_flash(:error, "No inventories found. Please create one.")
          |> redirect(to: "/inventories")
          |> halt()
        end

      _ ->
        inventory = find_inventory(inventory_id, inventories)
        admin_mode = get_session(conn, :admin_mode) || false
        inventory_role = inventory_role(user_id, inventory)

        unresolved_count =
          if inventory_role == :owner do
            Marketplace.count_unresolved_requests(inventory.id)
          else
            0
          end

        conn
        |> put_session(:inventory_id, inventory.id)
        |> assign(:current_inventory, inventory)
        |> assign(:inventories, inventories)
        |> assign(:admin_mode, admin_mode)
        |> assign(:inventory_role, inventory_role)
        |> assign(:unresolved_request_count, unresolved_count)
    end
  end

  @spec bypass_path?(String.t()) :: boolean()
  defp bypass_path?(path) do
    Enum.any?(@bypass_paths, &String.starts_with?(path, &1))
  end

  @spec find_inventory(integer() | nil, [Inv.t()]) :: Inv.t()
  defp find_inventory(nil, inventories), do: hd(inventories)

  defp find_inventory(inventory_id, inventories) do
    Enum.find(inventories, hd(inventories), fn inv -> inv.id == inventory_id end)
  end

  @spec inventory_role(integer(), Inv.t()) :: :owner | :viewer
  defp inventory_role(user_id, %Inv{user_id: user_id}), do: :owner
  defp inventory_role(_user_id, _inv), do: :viewer
end
