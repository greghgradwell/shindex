defmodule InventoryLocatorWeb.InventoryController do
  @moduledoc false
  use InventoryLocatorWeb, :controller

  alias InventoryLocator.Inventory

  @allowed_path_prefixes ["/", "/locations", "/projects", "/camera", "/inventories", "/share"]

  @spec switch(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def switch(conn, %{"inventory_id" => inventory_id_str}) do
    user_id = conn.assigns.current_user.id

    case Integer.parse(inventory_id_str) do
      {inventory_id, ""} when inventory_id > 0 ->
        if Inventory.user_can_access?(user_id, inventory_id) do
          redirect_path = get_safe_redirect_path(conn)

          conn
          |> put_session(:inventory_id, inventory_id)
          |> redirect(to: redirect_path)
        else
          conn
          |> put_flash(:error, "Inventory not found")
          |> redirect(to: "/")
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
