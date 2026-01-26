defmodule InventoryLocatorWeb.Plugs.RateLimiter do
  @moduledoc """
  Simple rate limiter for API endpoints using ETS.
  Limits requests per IP address to prevent abuse of polling endpoints.
  """
  import Plug.Conn

  require Logger

  @table_name :rate_limiter
  @max_requests 60
  @window_seconds 60

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    max_requests = Keyword.get(opts, :max_requests, @max_requests)
    window_seconds = Keyword.get(opts, :window_seconds, @window_seconds)

    ensure_table_exists()

    ip = get_remote_ip(conn)
    key = {conn.request_path, ip}
    now = System.system_time(:second)

    case check_rate_limit(key, now, max_requests, window_seconds) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        Logger.warning("Rate limit exceeded for #{inspect(ip)} on #{conn.request_path}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "Rate limit exceeded. Try again later."}))
        |> halt()
    end
  end

  @spec ensure_table_exists() :: :ok
  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        _ = :ets.new(@table_name, [:public, :named_table, :set])
        :ok

      _table ->
        :ok
    end
  end

  @spec check_rate_limit(term(), integer(), integer(), integer()) ::
          :ok | {:error, :rate_limited}
  defp check_rate_limit(key, now, max_requests, window_seconds) do
    window_start = now - window_seconds

    case :ets.lookup(@table_name, key) do
      [] ->
        :ets.insert(@table_name, {key, [{now, 1}]})
        :ok

      [{^key, requests}] ->
        active_requests = Enum.filter(requests, fn {timestamp, _count} -> timestamp > window_start end)
        total_count = Enum.sum(Enum.map(active_requests, fn {_ts, count} -> count end))

        if total_count >= max_requests do
          {:error, :rate_limited}
        else
          updated_requests = Enum.take([{now, 1} | active_requests], 100)
          :ets.insert(@table_name, {key, updated_requests})
          :ok
        end
    end
  end

  @spec get_remote_ip(Plug.Conn.t()) :: String.t()
  defp get_remote_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> to_string(:inet_parse.ntoa(conn.remote_ip))
    end
  end
end
