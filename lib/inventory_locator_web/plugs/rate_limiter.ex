defmodule InventoryLocatorWeb.Plugs.RateLimiter do
  @moduledoc false
  import Plug.Conn

  require Logger

  @table_name :rate_limiter

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    max_requests = Keyword.fetch!(opts, :max_requests)
    window_seconds = Keyword.fetch!(opts, :window_seconds)

    ip = get_remote_ip(conn)
    key = {conn.request_path, ip}

    case check_rate(key, max_requests, window_seconds) do
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

  @spec check_rate(term(), pos_integer(), pos_integer()) :: :ok | {:error, :rate_limited}
  def check_rate(key, max_requests, window_seconds) do
    ensure_table_exists()
    now = System.system_time(:second)
    check_rate_limit(key, now, max_requests, window_seconds)
  end

  @spec get_remote_ip(Plug.Conn.t() | %{x_headers: list(), peer_ip: tuple()}) :: String.t()
  def get_remote_ip(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> to_string(:inet_parse.ntoa(conn.remote_ip))
    end
  end

  def get_remote_ip(%{x_headers: x_headers, peer_ip: peer_ip}) do
    case List.keyfind(x_headers, "x-forwarded-for", 0) do
      {"x-forwarded-for", ip} -> ip
      nil -> to_string(:inet_parse.ntoa(peer_ip))
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
end
