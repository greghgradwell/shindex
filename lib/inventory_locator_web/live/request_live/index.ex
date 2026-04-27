defmodule InventoryLocatorWeb.RequestLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.AuthHelpers

  alias InventoryLocator.Marketplace
  alias Phoenix.LiveView.Socket

  require Logger

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    inventory_id = socket.assigns.current_inventory.id
    role = socket.assigns.inventory_role

    if connected?(socket) do
      Phoenix.PubSub.subscribe(InventoryLocator.PubSub, "inventory:#{inventory_id}:requests")
    end

    requests = load_requests(socket.assigns.current_user.id, inventory_id, role)

    socket =
      socket
      |> assign(:page_title, "Requests")
      |> assign(:filter, :unresolved)
      |> assign(:requests, requests)

    {:ok, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("filter", %{"filter" => "all"}, socket) do
    {:noreply, assign(socket, :filter, :all)}
  end

  def handle_event("filter", %{"filter" => "unresolved"}, socket) do
    {:noreply, assign(socket, :filter, :unresolved)}
  end

  def handle_event("filter", %{"filter" => _unknown}, socket) do
    {:noreply, socket}
  end

  def handle_event("resolve", %{"id" => id_str}, socket) do
    require_owner(socket, fn socket ->
      inventory_id = socket.assigns.current_inventory.id

      with {request_id, _} <- Integer.parse(id_str),
           request when not is_nil(request) <- Marketplace.get_request_for_inventory(request_id, inventory_id),
           {:ok, _} <- Marketplace.resolve_request(request) do
        {:noreply, socket |> reload_requests() |> put_flash(:info, "Request resolved")}
      else
        :error ->
          {:noreply, put_flash(socket, :error, "Invalid request ID")}

        nil ->
          {:noreply, put_flash(socket, :error, "Request not found")}

        {:error, changeset} ->
          Logger.warning("Failed to resolve request: #{inspect(changeset.errors)}")
          {:noreply, put_flash(socket, :error, "Failed to resolve request")}
      end
    end)
  end

  def handle_event("unresolve", %{"id" => id_str}, socket) do
    require_owner(socket, fn socket ->
      inventory_id = socket.assigns.current_inventory.id

      with {request_id, _} <- Integer.parse(id_str),
           request when not is_nil(request) <- Marketplace.get_request_for_inventory(request_id, inventory_id),
           {:ok, _} <- Marketplace.unresolve_request(request) do
        {:noreply, socket |> reload_requests() |> put_flash(:info, "Request reopened")}
      else
        :error ->
          {:noreply, put_flash(socket, :error, "Invalid request ID")}

        nil ->
          {:noreply, put_flash(socket, :error, "Request not found")}

        {:error, changeset} ->
          Logger.warning("Failed to unresolve request: #{inspect(changeset.errors)}")
          {:noreply, put_flash(socket, :error, "Failed to reopen request")}
      end
    end)
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info(:new_request, socket) do
    {:noreply, reload_requests(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @spec load_requests(integer(), integer(), :owner | :member | :guest | :none) :: [Marketplace.Request.t()]
  defp load_requests(_user_id, inventory_id, :owner) do
    Marketplace.list_requests_for_inventory(inventory_id)
  end

  defp load_requests(user_id, inventory_id, _role) do
    Marketplace.list_requests_by_user(user_id, inventory_id)
  end

  @spec reload_requests(Socket.t()) :: Socket.t()
  defp reload_requests(socket) do
    requests =
      load_requests(
        socket.assigns.current_user.id,
        socket.assigns.current_inventory.id,
        socket.assigns.inventory_role
      )

    assign(socket, :requests, requests)
  end

  @spec filtered_requests([Marketplace.Request.t()], :unresolved | :all) :: [Marketplace.Request.t()]
  defp filtered_requests(requests, :all), do: requests

  defp filtered_requests(requests, :unresolved) do
    Enum.filter(requests, fn r -> not r.resolved end)
  end
end
