defmodule InventoryLocatorWeb.Plugs.LoadInventory do
  @moduledoc false
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  import Plug.Conn

  alias InventoryLocator.Inventory

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    inventory_id = get_session(conn, :inventory_id)
    inventories = Inventory.list_inventories()

    case inventories do
      [] ->
        conn
        |> put_flash(:error, "No inventories found. Please create one.")
        |> redirect(to: "/inventories")
        |> halt()

      _ ->
        inventory = find_inventory(inventory_id, inventories)
        admin_mode = get_session(conn, :admin_mode) || false

        conn
        |> put_session(:inventory_id, inventory.id)
        |> assign(:current_inventory, inventory)
        |> assign(:inventories, inventories)
        |> assign(:admin_mode, admin_mode)
    end
  end

  @spec find_inventory(integer() | nil, [Inventory.Inv.t()]) :: Inventory.Inv.t()
  defp find_inventory(nil, inventories), do: hd(inventories)

  defp find_inventory(inventory_id, inventories) do
    Enum.find(inventories, hd(inventories), fn inv -> inv.id == inventory_id end)
  end
end
