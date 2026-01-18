defmodule InventoryLocatorWeb.AdminController do
  use InventoryLocatorWeb, :controller

  @spec toggle(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def toggle(conn, _params) do
    current = get_session(conn, :admin_mode) || false
    referer = conn |> get_req_header("referer") |> List.first() || "/"

    redirect_path = extract_path(referer)

    conn
    |> put_session(:admin_mode, !current)
    |> redirect(to: redirect_path)
  end

  @spec extract_path(String.t()) :: String.t()
  defp extract_path(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) and path != "" -> path
      _ -> "/"
    end
  end
end
