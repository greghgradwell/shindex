defmodule InventoryLocatorWeb.InventoryController do
  @moduledoc false
  use InventoryLocatorWeb, :controller

  alias InventoryLocator.Inventory

  @allowed_path_prefixes ["/", "/locations", "/projects", "/camera", "/inventories"]

  @spec switch(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def switch(conn, %{"inventory_id" => inventory_id_str}) do
    case Integer.parse(inventory_id_str) do
      {inventory_id, ""} when inventory_id > 0 ->
        case Inventory.get_inventory(inventory_id) do
          nil ->
            conn
            |> put_flash(:error, "Inventory not found")
            |> redirect(to: "/")

          _inventory ->
            redirect_path = get_safe_redirect_path(conn)

            conn
            |> put_session(:inventory_id, inventory_id)
            |> redirect(to: redirect_path)
        end

      _ ->
        conn
        |> put_flash(:error, "Invalid inventory ID")
        |> redirect(to: "/")
    end
  end

  @spec get_safe_redirect_path(Plug.Conn.t()) :: String.t()
  defp get_safe_redirect_path(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] ->
        uri = URI.parse(referer)
        validate_redirect_path(uri.path)

      [] ->
        "/"
    end
  end

  @spec validate_redirect_path(String.t() | nil) :: String.t()
  defp validate_redirect_path(nil), do: "/"

  defp validate_redirect_path(path) do
    cond do
      not String.starts_with?(path, "/") ->
        "/"

      String.contains?(path, "//") ->
        "/"

      Enum.any?(@allowed_path_prefixes, &String.starts_with?(path, &1)) ->
        path

      true ->
        "/"
    end
  end
end
