defmodule InventoryLocator.Backup.MaintenanceMode do
  @moduledoc false
  use Agent

  require Logger

  @pubsub InventoryLocator.PubSub
  @topic "maintenance:state"

  @type state :: %{
          active: boolean(),
          reason: String.t() | nil,
          started_at: DateTime.t() | nil
        }

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @spec active?() :: boolean()
  def active? do
    Agent.get(__MODULE__, & &1.active)
  end

  @spec get_state() :: state()
  def get_state do
    Agent.get(__MODULE__, & &1)
  end

  @spec activate(String.t()) :: :ok
  def activate(reason) do
    Agent.update(__MODULE__, fn _state ->
      %{
        active: true,
        reason: reason,
        started_at: DateTime.utc_now()
      }
    end)

    log_broadcast_result(broadcast_state())
    :ok
  end

  @spec deactivate() :: :ok
  def deactivate do
    Agent.update(__MODULE__, fn _state ->
      initial_state()
    end)

    log_broadcast_result(broadcast_state())
    :ok
  end

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @spec initial_state() :: state()
  defp initial_state do
    %{
      active: false,
      reason: nil,
      started_at: nil
    }
  end

  @spec broadcast_state() :: :ok | {:error, term()}
  defp broadcast_state do
    state = get_state()
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:maintenance_state, state})
  end

  @spec log_broadcast_result(:ok | {:error, term()}) :: :ok
  defp log_broadcast_result(:ok), do: :ok

  defp log_broadcast_result({:error, reason}) do
    Logger.warning("Failed to broadcast maintenance state: #{inspect(reason)}")
    :ok
  end
end
