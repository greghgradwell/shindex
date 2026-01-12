defmodule InventoryLocator.Search.AI do
  @moduledoc false

  alias InventoryLocator.Inventory.ItemType

  require Logger

  @api_url "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

  @spec search(String.t(), [ItemType.t()]) :: {:ok, [integer()]} | {:error, term()}
  def search(query, items) do
    prompt = build_prompt(query, items)

    case call_gemini(prompt) do
      {:ok, response} -> parse_response(response, items)
      {:error, _} = error -> error
    end
  end

  @spec build_prompt(String.t(), [ItemType.t()]) :: String.t()
  defp build_prompt(query, items) do
    item_list =
      Enum.map_join(items, "\n", fn item ->
        "ID:#{item.id} | #{item.name} | #{item.manufacturer || ""} | #{item.description || ""}"
      end)

    """
    You are a search assistant for an inventory system. Given a user's search query and a list of items, return the IDs of items that semantically match the query.

    Search query: "#{query}"

    Items:
    #{item_list}

    Return ONLY a JSON array of matching item IDs, ordered by relevance. Example: [42, 17, 8]
    If no items match, return an empty array: []
    """
  end

  @spec call_gemini(String.t()) :: {:ok, map()} | {:error, term()}
  defp call_gemini(prompt) do
    case Application.get_env(:inventory_locator, :gemini_api_key) do
      nil ->
        Logger.error("GEMINI_API_KEY not configured")
        {:error, :missing_api_key}

      api_key ->
        do_gemini_request(prompt, api_key)
    end
  end

  @spec do_gemini_request(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defp do_gemini_request(prompt, api_key) do
    headers = [{"x-goog-api-key", api_key}]

    body = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: %{temperature: 0.1, maxOutputTokens: 8192}
    }

    case Req.post(@api_url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:api_error, status, body}}
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  @spec parse_response(map(), [ItemType.t()]) :: {:ok, [integer()]} | {:error, term()}
  defp parse_response(response, items) do
    finish_reason = get_in(response, ["candidates", Access.at(0), "finishReason"])

    if finish_reason not in [nil, "STOP"] do
      Logger.warning("Gemini response truncated or blocked: #{finish_reason}")
    end

    text =
      get_in(response, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])

    extract_ids(text, items)
  end

  @spec extract_ids(String.t() | nil, [ItemType.t()]) :: {:ok, [integer()]}
  defp extract_ids(nil, _items), do: {:ok, []}
  defp extract_ids("", _items), do: {:ok, []}

  defp extract_ids(text, items) do
    valid_ids = MapSet.new(Enum.map(items, & &1.id))

    cleaned = text |> String.trim() |> strip_markdown_code_block()

    case Jason.decode(cleaned) do
      {:ok, ids} when is_list(ids) ->
        {:ok, filter_valid_ids(ids, valid_ids)}

      {:error, _} ->
        # JSON failed - try to salvage partial array with regex
        case Regex.scan(~r/\b(\d+)\b/, cleaned) do
          [] ->
            Logger.error("Could not extract any IDs from: #{inspect(cleaned)}")
            {:ok, []}

          matches ->
            ids =
              matches
              |> Enum.map(fn [_, id_str] -> String.to_integer(id_str) end)
              |> filter_valid_ids(valid_ids)

            Logger.info("Salvaged #{length(ids)} IDs from malformed response")
            {:ok, ids}
        end
    end
  end

  @spec filter_valid_ids([integer()], MapSet.t()) :: [integer()]
  defp filter_valid_ids(ids, valid_ids) do
    Enum.filter(ids, &MapSet.member?(valid_ids, &1))
  end

  @spec strip_markdown_code_block(String.t()) :: String.t()
  defp strip_markdown_code_block(text) do
    cond do
      String.starts_with?(text, "```json") ->
        text
        |> String.replace_prefix("```json", "")
        |> String.replace_suffix("```", "")
        |> String.trim()

      String.starts_with?(text, "```") ->
        text
        |> String.replace_prefix("```", "")
        |> String.replace_suffix("```", "")
        |> String.trim()

      true ->
        text
    end
  end
end
