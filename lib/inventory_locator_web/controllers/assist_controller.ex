defmodule InventoryLocatorWeb.AssistController do
  @moduledoc false
  use InventoryLocatorWeb, :controller

  alias InventoryLocator.Assist
  alias InventoryLocator.Assist.Decisions
  alias InventoryLocatorWeb.AssistHelpers

  require Logger

  @spec list_items(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_items(conn, params) do
    inventory_id = get_inventory_id(conn, params)

    field_results =
      params
      |> Map.get("fields", "manufacturer,model,description")
      |> String.split(",")
      |> Enum.map(&AssistHelpers.safe_to_field_atom/1)

    case Enum.find(field_results, &match?({:error, _}, &1)) do
      {:error, :invalid_field} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid field name. Valid fields: manufacturer, model, description"})

      nil ->
        fields = Enum.map(field_results, fn {:ok, f} -> f end)
        limit = safe_to_positive_integer(Map.get(params, "limit", "50"), 50)

        items = Assist.list_incomplete_items(inventory_id, %{fields: fields, limit: limit})
        total_count = Assist.count_incomplete_items(inventory_id, fields)
        json(conn, %{items: items, count: length(items), total_count: total_count})
    end
  end

  @spec get_item(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get_item(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {item_id, ""} ->
        case Assist.get_item(item_id) do
          {:ok, item} ->
            json(conn, %{item: item})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Item not found"})
        end

      _invalid ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid item ID"})
    end
  end

  @spec show_item(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_item(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {item_id, ""} ->
        Assist.show_item(item_id)
        json(conn, %{status: "ok", message: "Item #{item_id} displayed in browser"})

      _invalid ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid item ID"})
    end
  end

  @spec update_item(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update_item(conn, %{"id" => id} = params) do
    case Integer.parse(id) do
      {item_id, ""} ->
        attrs =
          params
          |> Map.take(["manufacturer", "model", "description"])
          |> Map.new(fn {k, _v} = pair ->
            {:ok, atom} = AssistHelpers.safe_to_field_atom(k)
            {atom, elem(pair, 1)}
          end)

        case Assist.update_item(item_id, attrs) do
          {:ok, item} ->
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

      _invalid ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid item ID"})
    end
  end

  @spec skip_fields(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def skip_fields(conn, %{"id" => id, "fields" => fields}) when is_list(fields) do
    case Integer.parse(id) do
      {item_id, ""} ->
        field_results = Enum.map(fields, &AssistHelpers.safe_to_field_atom/1)

        case Enum.find(field_results, &match?({:error, _}, &1)) do
          {:error, :invalid_field} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Invalid field name. Valid fields: manufacturer, model, description"})

          nil ->
            field_atoms = Enum.map(field_results, fn {:ok, f} -> f end)

            case Assist.skip_fields(item_id, field_atoms) do
              {:ok, _item} ->
                json(conn, %{status: "ok", message: "Fields skipped: #{Enum.join(fields, ", ")}"})

              {:error, :not_found} ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Item not found"})

              {:error, changeset} ->
                Logger.warning("Failed to skip fields: #{inspect(changeset)}")

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Failed to skip fields"})
            end
        end

      _invalid ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid item ID"})
    end
  end

  def skip_fields(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing 'fields' array in request body"})
  end

  @spec start_batch(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def start_batch(conn, %{"item_ids" => item_ids}) when is_list(item_ids) do
    case collect_items(item_ids) do
      {:ok, items} ->
        Decisions.clear()
        Decisions.start_batch(items)
        _ = Assist.show_batch(items)
        json(conn, %{status: "ok", count: length(item_ids)})

      {:error, missing_ids} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Items not found", missing_ids: missing_ids})
    end
  end

  def start_batch(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing 'item_ids' array in request body"})
  end

  @spec get_decisions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get_decisions(conn, _params) do
    case Decisions.get_decisions() do
      nil ->
        json(conn, %{status: "waiting"})

      decisions ->
        items =
          Enum.map(decisions.items, fn item ->
            %{
              item_id: item.item_id,
              item_name: item.item_name,
              find: Enum.map(item.find, &Atom.to_string/1),
              skip: Enum.map(item.skip, &Atom.to_string/1)
            }
          end)

        json(conn, %{status: "ready", batch_id: decisions.batch_id, items: items})
    end
  end

  @spec clear_batch(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def clear_batch(conn, _params) do
    Decisions.clear()
    json(conn, %{status: "ok"})
  end

  # ============================================================
  # Review endpoints
  # ============================================================

  @spec start_review(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def start_review(conn, %{"id" => id, "suggestions" => suggestions}) when is_map(suggestions) do
    case Integer.parse(id) do
      {item_id, ""} ->
        case Assist.get_item(item_id) do
          {:ok, item} ->
            suggestion_atoms = parse_suggestions(suggestions)
            Decisions.clear_review()
            Decisions.start_review(item_id, suggestion_atoms)
            _ = Assist.show_review(item, suggestion_atoms)
            json(conn, %{status: "ok", item_id: item_id})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Item not found"})
        end

      _invalid ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid item ID"})
    end
  end

  def start_review(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing 'suggestions' object in request body"})
  end

  @spec get_review_decision(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get_review_decision(conn, _params) do
    case Decisions.get_review_decision() do
      nil ->
        json(conn, %{status: "waiting"})

      review ->
        accepted =
          Map.new(review.accepted, fn {k, v} -> {Atom.to_string(k), v} end)

        json(conn, %{status: "ready", item_id: review.item_id, accepted: accepted})
    end
  end

  @spec clear_review(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def clear_review(conn, _params) do
    Decisions.clear_review()
    json(conn, %{status: "ok"})
  end

  # ============================================================
  # Batch review endpoints
  # ============================================================

  @spec add_batch_suggestions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def add_batch_suggestions(conn, %{"item_id" => item_id, "suggestions" => suggestions})
      when is_integer(item_id) and is_map(suggestions) do
    suggestion_atoms = parse_suggestions(suggestions)

    case Decisions.add_suggestions(item_id, suggestion_atoms) do
      :ok ->
        json(conn, %{status: "ok", item_id: item_id})

      {:error, :no_batch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No active batch"})
    end
  end

  def add_batch_suggestions(conn, %{"item_id" => item_id_str, "suggestions" => suggestions})
      when is_binary(item_id_str) and is_map(suggestions) do
    case Integer.parse(item_id_str) do
      {item_id, ""} ->
        add_batch_suggestions(conn, %{"item_id" => item_id, "suggestions" => suggestions})

      _invalid ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid item_id"})
    end
  end

  def add_batch_suggestions(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing item_id or suggestions"})
  end

  @spec mark_review_ready(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def mark_review_ready(conn, _params) do
    case Decisions.mark_review_ready() do
      :ok ->
        case Decisions.get_batch_suggestions() do
          nil ->
            json(conn, %{status: "ok"})

          %{batch: batch} ->
            items_with_suggestions =
              Enum.flat_map(batch.suggestions, fn {item_id, suggestions} ->
                case Assist.get_item(item_id) do
                  {:ok, item} ->
                    [{item, suggestions}]

                  {:error, :not_found} ->
                    Logger.warning("Item #{item_id} not found during batch review preparation")
                    []
                end
              end)

            _ = Assist.show_batch_review(items_with_suggestions)

            json(conn, %{
              status: "ok",
              items_count: length(items_with_suggestions)
            })
        end

      {:error, :no_batch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No active batch"})
    end
  end

  @spec get_batch_review_decision(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get_batch_review_decision(conn, _params) do
    case Decisions.get_batch_review_decision() do
      nil ->
        json(conn, %{status: "waiting"})

      %{batch_id: batch_id, accepted: accepted} ->
        serialized_accepted =
          Map.new(accepted, fn {item_id, fields} ->
            field_strings = Map.new(fields, fn {k, v} -> {Atom.to_string(k), v} end)
            {to_string(item_id), field_strings}
          end)

        json(conn, %{status: "ready", batch_id: batch_id, accepted: serialized_accepted})
    end
  end

  @spec parse_suggestions(map()) :: %{atom() => String.t()}
  defp parse_suggestions(suggestions) do
    valid_fields = AssistHelpers.valid_fields()

    suggestions
    |> Enum.filter(fn {k, _v} -> k in ["manufacturer", "model", "description"] end)
    |> Map.new(fn {k, v} ->
      atom = String.to_existing_atom(k)

      if atom in valid_fields do
        {atom, v}
      else
        raise ArgumentError, "Invalid field: #{k}"
      end
    end)
  end

  @spec get_inventory_id(Plug.Conn.t(), map()) :: integer()
  defp get_inventory_id(conn, params) do
    case Map.get(params, "inventory_id") do
      nil ->
        conn.assigns[:current_inventory].id

      id_str ->
        case Integer.parse(id_str) do
          {id, ""} -> id
          _invalid -> conn.assigns[:current_inventory].id
        end
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

  @spec safe_to_positive_integer(String.t(), pos_integer()) :: pos_integer()
  defp safe_to_positive_integer(str, default) do
    case Integer.parse(str) do
      {num, ""} when num > 0 -> num
      _other -> default
    end
  end

  @spec collect_items([integer()]) :: {:ok, [Assist.item_summary()]} | {:error, [integer()]}
  defp collect_items(item_ids) do
    results = Enum.map(item_ids, fn id -> {id, Assist.get_item(id)} end)
    errors = for {id, {:error, :not_found}} <- results, do: id

    if errors == [] do
      items = for {_id, {:ok, item}} <- results, do: item
      {:ok, items}
    else
      {:error, errors}
    end
  end
end
