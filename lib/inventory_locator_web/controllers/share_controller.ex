defmodule InventoryLocatorWeb.ShareController do
  @moduledoc false
  use InventoryLocatorWeb, :controller

  alias InventoryLocator.Inventory

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"code" => code}) do
    case Inventory.get_share_code_info(code) do
      nil ->
        conn
        |> put_flash(:error, "Invalid or expired share link.")
        |> redirect(to: "/")

      info ->
        render(conn, :show, code: code, info: info)
    end
  end

  @spec enter_guest(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def enter_guest(conn, %{"code" => code}) do
    case Inventory.resolve_public_code(code) do
      {:ok, inventory} ->
        conn
        |> put_session(:guest_inventory_id, inventory.id)
        |> redirect(to: "/")

      :invalid ->
        conn
        |> put_flash(:error, "Invalid or expired view link.")
        |> redirect(to: "/landing")
    end
  end

  @spec redeem(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def redeem(conn, %{"code" => code}) do
    user_id = conn.assigns.current_user.id

    case Inventory.redeem_share_code(code, user_id) do
      {:ok, _member} ->
        conn
        |> put_flash(:info, "You now have access to the shared inventory.")
        |> redirect(to: "/inventories")

      {:error, :invalid_code} ->
        conn
        |> put_flash(:error, "Invalid or expired share link.")
        |> redirect(to: "/")

      {:error, :already_member} ->
        conn
        |> put_flash(:info, "You already have access to this inventory.")
        |> redirect(to: "/inventories")

      {:error, :own_inventory} ->
        conn
        |> put_flash(:info, "You own this inventory.")
        |> redirect(to: "/inventories")
    end
  end
end
