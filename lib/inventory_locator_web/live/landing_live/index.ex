defmodule InventoryLocatorWeb.LandingLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Auth
  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, session, socket) do
    if not Auth.auth_required?() or session["user_id"] do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Welcome")
       |> assign(:guest_code, "")
       |> assign(:guest_error, nil)}
    end
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("update_guest_code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :guest_code, code)}
  end

  def handle_event("submit_guest_code", _params, socket) do
    code = String.trim(socket.assigns.guest_code)

    case Inventory.resolve_public_code(code) do
      {:ok, _inventory} ->
        {:noreply, push_navigate(socket, to: ~p"/view/#{code}")}

      :invalid ->
        {:noreply, assign(socket, :guest_error, "Invalid or expired code.")}
    end
  end
end
