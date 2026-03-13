defmodule InventoryLocator.Application do
  @moduledoc false

  use Application

  alias InventoryLocator.Backup.Scheduler

  @impl true
  def start(_type, _args) do
    validate_required_env_vars()

    children = [
      InventoryLocatorWeb.Telemetry,
      InventoryLocator.Repo,
      {DNSCluster, query: Application.get_env(:inventory_locator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: InventoryLocator.PubSub},
      InventoryLocator.Assist.Decisions,
      InventoryLocator.Backup.MaintenanceMode,
      Scheduler,
      InventoryLocatorWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: InventoryLocator.Supervisor]
    result = Supervisor.start_link(children, opts)

    configure_backup_scheduler()
    ensure_local_user_if_needed()

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    InventoryLocatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @spec validate_required_env_vars() :: :ok
  defp validate_required_env_vars do
    require Logger

    required_vars = [
      {"GEMINI_API_KEY", "Gemini API for AI-powered features"},
      {"TAVILY_API_KEY", "Tavily API for web search functionality"}
    ]

    missing =
      Enum.filter(required_vars, fn {var, _desc} ->
        case System.get_env(var) do
          nil -> true
          "" -> true
          _value -> false
        end
      end)

    if missing != [] do
      Logger.warning("Missing required environment variables:")

      Enum.each(missing, fn {var, desc} ->
        Logger.warning("  - #{var}: #{desc}")
      end)

      Logger.warning("Some features may not work correctly. Set these in your .envrc or environment.")
    end

    :ok
  end

  @spec ensure_local_user_if_needed() :: :ok
  defp ensure_local_user_if_needed do
    _ =
      Task.start(fn ->
        Process.sleep(1000)

        try do
          InventoryLocator.Auth.ensure_local_user()
        rescue
          e ->
            require Logger

            Logger.error("Failed to ensure local user: #{Exception.message(e)}")
        end
      end)

    :ok
  end

  @spec configure_backup_scheduler() :: :ok
  defp configure_backup_scheduler do
    _ =
      Task.start(fn ->
        Process.sleep(1000)

        try do
          settings = InventoryLocator.Backup.get_settings()
          Scheduler.configure_from_settings(settings)
        rescue
          e ->
            require Logger

            Logger.error("Failed to configure backup scheduler: #{Exception.message(e)}")
        end
      end)

    :ok
  end
end
