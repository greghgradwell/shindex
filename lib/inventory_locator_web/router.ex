defmodule InventoryLocatorWeb.Router do
  use InventoryLocatorWeb, :router

  alias InventoryLocatorWeb.Hooks.AuthHook
  alias InventoryLocatorWeb.Hooks.InventoryHook
  alias InventoryLocatorWeb.Plugs.LoadInventory
  alias InventoryLocatorWeb.Plugs.RateLimiter
  alias InventoryLocatorWeb.Plugs.RequireAuthenticated

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InventoryLocatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug RequireAuthenticated
    plug LoadInventory
  end

  pipeline :browser_public do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InventoryLocatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :rate_limit_auth do
    plug RateLimiter, max_requests: 10, window_seconds: 60
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_protected do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug RequireAuthenticated
    plug LoadInventory
    plug RateLimiter, max_requests: 60, window_seconds: 60
  end

  # Local dev API - no CSRF (for CLI scripts), rate-limited
  pipeline :api_dev do
    plug :accepts, ["json"]
    plug :fetch_session
    plug RequireAuthenticated
    plug LoadInventory
    plug RateLimiter, max_requests: 60, window_seconds: 60
  end

  scope "/", InventoryLocatorWeb do
    pipe_through :browser_public

    live_session :public,
      layout: {InventoryLocatorWeb.Layouts, :public} do
      live "/landing", LandingLive.Index
    end
  end

  scope "/auth", InventoryLocatorWeb do
    pipe_through [:browser_public, :rate_limit_auth]

    get "/register", AuthController, :register
    post "/register", AuthController, :create_registration
    post "/logout", AuthController, :logout
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", InventoryLocatorWeb do
    pipe_through :browser

    post "/switch_inventory", InventoryController, :switch
    post "/admin/toggle", AdminController, :toggle

    live_session :default,
      on_mount: [AuthHook, InventoryHook],
      layout: {InventoryLocatorWeb.Layouts, :app} do
      live "/", ItemLive.Index
      live "/locations", LocationLive.Index
      live "/projects", ProjectLive.Index
      live "/inventories", InventoryLive.Index
      live "/backups", BackupLive.Index
      live "/invites", InviteLive.Index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:inventory_locator, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: InventoryLocatorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      live_session :dev,
        on_mount: [AuthHook, InventoryHook],
        layout: {InventoryLocatorWeb.Layouts, :app} do
        live "/assist", InventoryLocatorWeb.AssistLive.Index
      end
    end

    scope "/api/assist", InventoryLocatorWeb do
      pipe_through :api_dev

      get "/items", AssistController, :list_items
      get "/items/:id", AssistController, :get_item
      post "/items/:id/show", AssistController, :show_item
      patch "/items/:id", AssistController, :update_item
      post "/items/:id/skip", AssistController, :skip_fields

      post "/batch/start", AssistController, :start_batch
      get "/batch/decisions", AssistController, :get_decisions
      post "/batch/clear", AssistController, :clear_batch

      post "/batch/suggestions", AssistController, :add_batch_suggestions
      post "/batch/review-ready", AssistController, :mark_review_ready
      get "/batch/review-decision", AssistController, :get_batch_review_decision

      post "/items/:id/review", AssistController, :start_review
      get "/review/decision", AssistController, :get_review_decision
      post "/review/clear", AssistController, :clear_review
    end
  end
end
