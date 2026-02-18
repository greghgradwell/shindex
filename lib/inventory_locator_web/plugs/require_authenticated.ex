defmodule InventoryLocatorWeb.Plugs.RequireAuthenticated do
  @moduledoc false
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  import Plug.Conn

  alias InventoryLocator.Accounts

  require Logger

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> put_flash(:error, "Please sign in to continue.")
        |> redirect(to: "/landing")
        |> halt()

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            Logger.warning("Session user_id #{user_id} not found in database")

            conn
            |> configure_session(drop: true)
            |> put_flash(:error, "Session expired. Please sign in again.")
            |> redirect(to: "/landing")
            |> halt()

          user ->
            conn
            |> assign(:current_user, user)
            |> assign(:admin_user?, user.role == "admin")
        end
    end
  end
end
