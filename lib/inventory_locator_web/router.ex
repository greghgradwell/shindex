defmodule InventoryLocatorWeb.Router do
  use InventoryLocatorWeb, :router

  alias InventoryLocatorWeb.Hooks.InventoryHook
  alias InventoryLocatorWeb.Plugs.LoadInventory

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
      pipe_through [:api, :fetch_session, LoadInventory]

      get "/items", AssistController, :list_items
      get "/items/:id", AssistController, :get_item
      post "/items/:id/show", AssistController, :show_item
      patch "/items/:id", AssistController, :update_item
      post "/items/:id/skip", AssistController, :skip_fields

      post "/batch/start", AssistController, :start_batch
      get "/batch/decisions", AssistController, :get_decisions
      post "/batch/clear", AssistController, :clear_batch
    end
  end
end
