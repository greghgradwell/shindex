defmodule InventoryLocatorWeb.AssistController do
  @moduledoc false
  use InventoryLocatorWeb, :controller

  alias InventoryLocator.Assist

  @spec list_items(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_items(conn, params) do
    inventory_id = get_inventory_id(conn, params)

    fields =
      params
      |> Map.get("fields", "manufacturer,model,description")
      |> String.split(",")
      |> Enum.map(&String.to_existing_atom/1)

    limit = params |> Map.get("limit", "50") |> String.to_integer()

    items = Assist.list_incomplete_items(inventory_id, %{fields: fields, limit: limit})
    json(conn, %{items: items, count: length(items)})
  end

  @spec get_item(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get_item(conn, %{"id" => id}) do
    case Assist.get_item(String.to_integer(id)) do
      {:ok, item} ->
        json(conn, %{item: item})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})
    end
  end

  @spec show_item(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_item(conn, %{"id" => id}) do
    item_id = String.to_integer(id)
    Assist.show_item(item_id)
    json(conn, %{status: "ok", message: "Item #{item_id} displayed in browser"})
  end

  @spec update_item(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update_item(conn, %{"id" => id} = params) do
    item_id = String.to_integer(id)

    attrs =
      params
      |> Map.take(["manufacturer", "model", "description"])
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    case Assist.update_item(item_id, attrs) do
      {:ok, item} ->
        Assist.show_item(item_id)
        json(conn, %{status: "ok", item: summarize_item(item)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Update failed", details: format_changeset_errors(changeset)})
    end
  end

  @spec skip_fields(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def skip_fields(conn, %{"id" => id, "fields" => fields}) when is_list(fields) do
    item_id = String.to_integer(id)
    field_atoms = Enum.map(fields, &String.to_existing_atom/1)

    case Assist.skip_fields(item_id, field_atoms) do
      {:ok, _item} ->
        json(conn, %{status: "ok", message: "Fields skipped: #{Enum.join(fields, ", ")}"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to skip fields"})
    end
  end

  def skip_fields(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing 'fields' array in request body"})
  end

  @spec get_inventory_id(Plug.Conn.t(), map()) :: integer()
  defp get_inventory_id(conn, params) do
    case Map.get(params, "inventory_id") do
      nil ->
        conn.assigns[:current_inventory].id

      id_str ->
        String.to_integer(id_str)
    end
  end

  @spec summarize_item(InventoryLocator.Inventory.ItemType.t()) :: map()
  defp summarize_item(item) do
    %{
      id: item.id,
      name: item.name,
      manufacturer: item.manufacturer,
      model: item.model,
      description: item.description
    }
  end

  @spec format_changeset_errors(Ecto.Changeset.t()) :: map()
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
