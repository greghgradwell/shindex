defmodule InventoryLocatorWeb.Plugs.RateLimiter.Store do
  @moduledoc false
  use GenServer

  @table_name :rate_limiter
  @cleanup_interval to_timeout(minute: 5)
  # Drop entries whose every timestamp is older than the longest active window.
  # AI search uses a 24h daily cap; bump this if any new limit uses a longer window.
  @max_entry_age_seconds 86_400

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec table_name() :: atom()
  def table_name, do: @table_name

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    :ets.new(@table_name, [:public, :named_table, :set])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  @spec handle_info(:cleanup, map()) :: {:noreply, map()}
  def handle_info(:cleanup, state) do
    purge_stale(System.system_time(:second) - @max_entry_age_seconds)
    schedule_cleanup()
    {:noreply, state}
  end

  @spec purge_stale(integer()) :: :ok
  defp purge_stale(cutoff) do
    :ets.foldl(
      fn {key, requests}, _acc ->
        active = Enum.filter(requests, fn {ts, _count} -> ts > cutoff end)

        cond do
          active == [] -> :ets.delete(@table_name, key)
          active != requests -> :ets.insert(@table_name, {key, active})
          true -> :ok
        end
      end,
      :ok,
      @table_name
    )

    :ok
  end

  @spec schedule_cleanup() :: reference()
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
