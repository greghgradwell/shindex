defmodule InventoryLocatorWeb.AssistLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Assist
  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    _ = if connected?(socket), do: Assist.subscribe()

    socket =
      socket
      |> assign(:page_title, "Assist Mode")
      |> assign(:current_item, nil)

    {:ok, socket}
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:show_item, item_id}, socket) do
    item = Inventory.get_item_type_with_location!(item_id)
    {:noreply, assign(socket, :current_item, item)}
  end
end
