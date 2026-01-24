defmodule InventoryLocator.Application do
  @moduledoc false

  use Application

  alias InventoryLocator.Backup.Scheduler

  @impl true
  def start(_type, _args) do
    children = [
      InventoryLocatorWeb.Telemetry,
      InventoryLocator.Repo,
      {DNSCluster, query: Application.get_env(:inventory_locator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: InventoryLocator.PubSub},
      InventoryLocator.Backup.MaintenanceMode,
      Scheduler,
      InventoryLocatorWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: InventoryLocator.Supervisor]
    result = Supervisor.start_link(children, opts)

    configure_backup_scheduler()

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    InventoryLocatorWeb.Endpoint.config_change(changed, removed)
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
