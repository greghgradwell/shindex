defmodule InventoryLocatorWeb.LandingLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, session, socket) do
    if session["user_id"] do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {:ok, assign(socket, :page_title, "Welcome")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-[60vh] items-center justify-center">
      <div class="card bg-base-200 w-full max-w-md shadow-xl">
        <div class="card-body items-center text-center">
          <h1 class="card-title text-3xl">Shindex</h1>
          <p class="text-base-content/70 mt-2">Track and find your workshop items.</p>

          <div class="card-actions mt-6 flex-col gap-3 w-full">
            <a href={~p"/auth/linkedin"} class="btn btn-neutral w-full">
              <svg class="size-5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
              </svg>
              Sign in with LinkedIn
            </a>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
