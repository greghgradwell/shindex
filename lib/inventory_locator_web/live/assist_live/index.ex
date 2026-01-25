defmodule InventoryLocatorWeb.AssistLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Assist
  alias InventoryLocator.Assist.Decisions
  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  require Logger

  @valid_fields [:manufacturer, :model, :description]

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    _ = if connected?(socket), do: Assist.subscribe()

    socket =
      socket
      |> assign(:page_title, "Assist Mode")
      |> assign(:mode, :waiting)
      |> assign(:current_item, nil)
      |> assign(:batch_items, [])
      |> assign(:decisions, %{})

    {:ok, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("toggle_field", %{"item-id" => item_id_str, "field" => field_str}, socket) do
    with {item_id, ""} <- Integer.parse(item_id_str),
         {:ok, field} <- safe_to_field_atom(field_str) do
      decisions = socket.assigns.decisions
      item_decisions = Map.get(decisions, item_id, %{find: [], skip: []})

      updated_decisions =
        if field in item_decisions.find do
          %{item_decisions | find: List.delete(item_decisions.find, field), skip: [field | item_decisions.skip]}
        else
          %{item_decisions | find: [field | item_decisions.find], skip: List.delete(item_decisions.skip, field)}
        end

      new_decisions = Map.put(decisions, item_id, updated_decisions)
      _ = Decisions.update_item(item_id, updated_decisions.find, updated_decisions.skip)

      {:noreply, assign(socket, :decisions, new_decisions)}
    else
      invalid ->
        Logger.warning(
          "Invalid toggle_field params: item_id=#{inspect(item_id_str)}, field=#{inspect(field_str)}, error=#{inspect(invalid)}"
        )

        {:noreply, socket}
    end
  end

  def handle_event("submit_batch", _params, socket) do
    _ = Decisions.submit_batch()
    {:noreply, assign(socket, :mode, :submitted)}
  end

  def handle_event(event, params, socket) do
    Logger.warning("Unexpected event: #{inspect(event)}, params: #{inspect(params)}")
    {:noreply, socket}
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:show_item, item_id}, socket) do
    item = Inventory.get_item_type_with_location!(item_id)

    socket =
      socket
      |> assign(:current_item, item)
      |> assign(:mode, :review)

    {:noreply, socket}
  end

  def handle_info({:show_batch, items}, socket) do
    decisions =
      Map.new(items, fn item ->
        {item.id, %{find: item.missing_fields, skip: []}}
      end)

    socket =
      socket
      |> assign(:batch_items, items)
      |> assign(:decisions, decisions)
      |> assign(:mode, :batch)

    {:noreply, socket}
  end

  def handle_info(message, socket) do
    Logger.warning("Unexpected message: #{inspect(message)}")
    {:noreply, socket}
  end

  @spec safe_to_field_atom(String.t()) :: {:ok, atom()} | {:error, :invalid_field}
  defp safe_to_field_atom(str) do
    atom = String.to_existing_atom(str)

    if atom in @valid_fields do
      {:ok, atom}
    else
      {:error, :invalid_field}
    end
  rescue
    ArgumentError -> {:error, :invalid_field}
  end
end
