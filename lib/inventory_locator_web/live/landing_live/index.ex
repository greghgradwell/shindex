defmodule InventoryLocatorWeb.LandingLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Auth
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, session, socket) do
    if not Auth.auth_required?() or session["user_id"] do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {:ok, assign(socket, :page_title, "Welcome")}
    end
  end
end
