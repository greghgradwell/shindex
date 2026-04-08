defmodule InventoryLocatorWeb.AuthHelpers do
  @moduledoc false
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Phoenix.LiveView.Socket

  @spec require_admin(Socket.t(), (Socket.t() -> {:noreply, Socket.t()})) :: {:noreply, Socket.t()}
  def require_admin(socket, func) do
    if socket.assigns[:admin_user?] do
      func.(socket)
    else
      {:noreply, put_flash(socket, :error, "Admin access required.")}
    end
  end

  @spec require_owner(Socket.t(), (Socket.t() -> {:noreply, Socket.t()})) :: {:noreply, Socket.t()}
  def require_owner(socket, func) do
    if socket.assigns[:inventory_role] == :owner do
      func.(socket)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to modify this inventory.")}
    end
  end

  @spec require_member(Socket.t(), (Socket.t() -> {:noreply, Socket.t()})) :: {:noreply, Socket.t()}
  def require_member(socket, func) do
    if socket.assigns[:inventory_role] in [:owner, :member] do
      func.(socket)
    else
      {:noreply, put_flash(socket, :error, "Sign in to interact with this inventory.")}
    end
  end
end
