defmodule InventoryLocatorWeb.Hooks.AuthHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias InventoryLocator.Accounts
  alias Phoenix.LiveView.Socket

  require Logger

  @spec on_mount(atom(), map(), map(), Socket.t()) :: {:cont, Socket.t()} | {:halt, Socket.t()}
  def on_mount(:default, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, redirect(socket, to: "/landing")}

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            Logger.warning("LiveView session user_id #{user_id} not found in database")
            {:halt, redirect(socket, to: "/landing")}

          user ->
            socket =
              socket
              |> assign(:current_user, user)
              |> assign(:admin_user?, user.role == "admin")

            {:cont, socket}
        end
    end
  end
end
