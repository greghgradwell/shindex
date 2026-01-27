defmodule InventoryLocatorWeb.Router do
  use InventoryLocatorWeb, :router

  alias InventoryLocatorWeb.Hooks.InventoryHook
  alias InventoryLocatorWeb.Plugs.LoadInventory
  alias InventoryLocatorWeb.Plugs.RateLimiter

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InventoryLocatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LoadInventory
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_protected do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug LoadInventory
    plug RateLimiter, max_requests: 60, window_seconds: 60
  end

  # Local dev API - no CSRF (for CLI scripts), rate-limited
  pipeline :api_dev do
    plug :accepts, ["json"]
    plug :fetch_session
    plug LoadInventory
    plug RateLimiter, max_requests: 60, window_seconds: 60
  end

  scope "/", InventoryLocatorWeb do
    pipe_through :browser

    post "/switch_inventory", InventoryController, :switch
    post "/admin/toggle", AdminController, :toggle

    live_session :default,
      on_mount: [InventoryHook],
      layout: {InventoryLocatorWeb.Layouts, :app} do
      live "/", ItemLive.Index
      live "/locations", LocationLive.Index
      live "/projects", ProjectLive.Index
      live "/camera", CameraLive.Index
      live "/inventories", InventoryLive.Index
      live "/backups", BackupLive.Index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", InventoryLocatorWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:inventory_locator, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: InventoryLocatorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      live_session :dev,
        on_mount: [InventoryHook],
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
