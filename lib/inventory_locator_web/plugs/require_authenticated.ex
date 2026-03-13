defmodule InventoryLocatorWeb.Plugs.RequireAuthenticated do
  @moduledoc false
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  import Plug.Conn

  alias InventoryLocator.Auth

  require Logger

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    session = %{"user_id" => get_session(conn, :user_id)}

    case Auth.resolve_user(session) do
      {:ok, user} ->
        conn
        |> assign(:current_user, user)
        |> assign(:admin_user?, user.role == "admin")

      :stale_session ->
        Logger.warning("Session user_id #{session["user_id"]} not found in database")

        conn
        |> configure_session(drop: true)
        |> put_flash(:error, "Session expired. Please sign in again.")
        |> redirect(to: "/landing")
        |> halt()

      :unauthenticated ->
        conn
        |> put_flash(:error, "Please sign in to continue.")
        |> redirect(to: "/landing")
        |> halt()
    end
  end
end
