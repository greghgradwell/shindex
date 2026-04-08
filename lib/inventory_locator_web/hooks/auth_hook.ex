defmodule InventoryLocatorWeb.Hooks.AuthHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias InventoryLocator.Auth
  alias Phoenix.LiveView.Socket

  @spec on_mount(atom(), map(), map(), Socket.t()) :: {:cont, Socket.t()} | {:halt, Socket.t()}
  def on_mount(:default, _params, session, socket) do
    case Auth.resolve_user(session) do
      {:ok, user} ->
        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:admin_user?, user.role == "admin")}

      result when result in [:unauthenticated, :stale_session] ->
        if session["guest_inventory_id"] do
          {:cont,
           socket
           |> assign(:current_user, nil)
           |> assign(:admin_user?, false)
           |> assign(:guest_session, true)}
        else
          {:halt, redirect(socket, to: "/landing")}
        end
    end
  end
end
