defmodule InventoryLocatorWeb.ItemLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.AuthHelpers
  import InventoryLocatorWeb.ItemLive.Components

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Marketplace
  alias InventoryLocatorWeb.ItemLive.ShowModal
  alias InventoryLocatorWeb.Plugs.RateLimiter
  alias Phoenix.LiveView.Socket

  require Logger

  @page_size 48

  # Progressive rate limits for AI search: burst (per minute) + daily cap.
  # Each tuple is {max_requests, window_seconds}.
  @ai_search_limits [
    {10, 60},
    {50, 86_400}
  ]

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(params, _session, socket) do
    view_mode = if params["view"] == "table", do: :table, else: :search

    socket =
      socket
      |> assign_defaults()
      |> assign(:view_mode, view_mode)
      |> assign(:client_ip, get_client_ip(socket))

    socket = if view_mode == :table, do: load_all_items(socket), else: socket

    {:ok, socket}
  end

  @spec get_client_ip(Socket.t()) :: String.t() | nil
  defp get_client_ip(socket) do
    if connected?(socket) do
      peer_data = get_connect_info(socket, :peer_data)
      x_headers = get_connect_info(socket, :x_headers) || []

      case peer_data do
        %{address: peer_ip} ->
          RateLimiter.get_remote_ip(%{peer_ip: peer_ip, x_headers: x_headers})

        other ->
          Logger.warning("Unexpected peer_data shape in LiveView mount: #{inspect(other)}")
          nil
      end
    end
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:query, query)
      |> assign(:page, 1)
      |> perform_search()

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("toggle_archived", _params, socket) do
    socket =
      socket
      |> assign(:show_archived, !socket.assigns.show_archived)
      |> assign(:page, 1)
      |> refresh_current_view()

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("toggle_filter", %{"filter" => filter}, socket)
      when filter in ["manufacturer", "model", "description"] do
    filter_atom = String.to_existing_atom(filter)
    active_filters = toggle_filter_list(socket.assigns.active_filters, filter_atom)

    socket =
      socket
      |> assign(:active_filters, active_filters)
      |> assign(:page, 1)
      |> perform_search()

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_event("toggle_filter", %{"filter" => _unknown}, socket) do
    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("toggle_availability_filter", %{"type" => type}, socket) when type in ["borrow", "lease", "sale"] do
    filters = toggle_filter_list(socket.assigns.availability_filters, type)

    socket =
      socket
      |> assign(:availability_filters, filters)
      |> assign(:page, 1)
      |> refresh_current_view()

    {:noreply, socket}
  end

  def handle_event("toggle_availability_filter", %{"type" => _unknown}, socket) do
    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("open_item_modal", %{"id" => id}, socket) do
    item_id = String.to_integer(id)

    socket =
      if socket.assigns.active_filters == [] do
        socket
        |> assign(:selected_item_id, item_id)
        |> assign(:batch_mode, false)
        |> assign(:batch_item_ids, [])
      else
        batch_ids = Enum.map(socket.assigns.results, & &1.id)

        socket
        |> assign(:selected_item_id, item_id)
        |> assign(:batch_mode, true)
        |> assign(:batch_item_ids, batch_ids)
      end

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("create_new_item", _params, socket) do
    require_owner(socket, fn socket ->
      inventory_id = socket.assigns.current_inventory.id

      case Inventory.get_unsorted_location(inventory_id) do
        {:ok, location} ->
          case Inventory.create_item_type(%{
                 inventory_id: inventory_id,
                 location_id: location.id,
                 name: "New Item",
                 quantity: 1,
                 archived: false
               }) do
            {:ok, item} ->
              {:noreply,
               socket
               |> assign(:selected_item_id, item.id)
               |> assign(:start_editing, true)
               |> assign(:batch_mode, false)
               |> assign(:batch_item_ids, [])}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to create item")}
          end

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to get default location")}
      end
    end)
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("sort", %{"column" => column}, socket) when column in ["name", "manufacturer", "model", "location"] do
    column_atom =
      case column do
        "name" -> :name
        "manufacturer" -> :manufacturer
        "model" -> :model
        "location" -> :location
      end

    {sort_by, sort_order} =
      if socket.assigns.sort_by == column_atom do
        new_order = if socket.assigns.sort_order == :asc, do: :desc, else: :asc
        {column_atom, new_order}
      else
        {column_atom, :asc}
      end

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign(:page, 1)
      |> load_all_items()

    {:noreply, socket}
  end

  def handle_event("sort", %{"column" => _invalid}, socket) do
    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("change_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    max_page = max(ceil(socket.assigns.total_count / @page_size), 1)
    page = page |> max(1) |> min(max_page)

    socket =
      socket
      |> assign(:page, page)
      |> refresh_current_view()

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("submit_search", %{"query" => query}, socket) do
    socket = assign(socket, :query, query)
    results_count = length(socket.assigns.results)

    socket =
      if query == "" do
        socket
      else
        socket
        |> assign(:show_ai_modal, true)
        |> assign(:ai_modal_type, if(results_count == 0, do: :no_results, else: :has_results))
      end

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("confirm_ai_search", _params, socket) do
    case check_ai_search_rate_limit(socket) do
      :ok ->
        socket =
          socket
          |> assign(:show_ai_modal, false)
          |> assign(:ai_loading, true)

        all_items =
          Inventory.list_all_items_unpaginated(socket.assigns.current_inventory.id,
            show_archived: socket.assigns.show_archived
          )

        send(self(), {:perform_ai_search, socket.assigns.query, all_items})

        {:noreply, socket}

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> assign(:show_ai_modal, false)
         |> put_flash(:error, "AI search limit reached. Please try again later.")}

      {:error, :no_ip} ->
        {:noreply,
         socket
         |> assign(:show_ai_modal, false)
         |> put_flash(:error, "AI search is temporarily unavailable.")}
    end
  end

  @spec check_ai_search_rate_limit(Socket.t()) :: :ok | {:error, :rate_limited | :no_ip}
  defp check_ai_search_rate_limit(socket) do
    case socket.assigns[:client_ip] do
      nil -> {:error, :no_ip}
      ip -> check_ai_search_limits(ip, @ai_search_limits)
    end
  end

  @spec check_ai_search_limits(String.t(), [{pos_integer(), pos_integer()}]) ::
          :ok | {:error, :rate_limited}
  defp check_ai_search_limits(_ip, []), do: :ok

  defp check_ai_search_limits(ip, [{max, window} | rest]) do
    case RateLimiter.check_rate({:ai_search, ip, window}, max, window) do
      :ok -> check_ai_search_limits(ip, rest)
      {:error, :rate_limited} = error -> error
    end
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("close_ai_modal", _params, socket) do
    {:noreply, assign(socket, :show_ai_modal, false)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("clear_ai_results", _params, socket) do
    {:noreply, assign(socket, ai_results: nil, ai_query: nil)}
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:close_item_modal}, socket) do
    {:noreply, socket |> reset_batch_state() |> refresh_current_view()}
  end

  @impl true
  @spec handle_info({:perform_ai_search, String.t(), [map()]}, Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_info({:perform_ai_search, query, items}, socket) do
    alias InventoryLocator.Search.AI

    socket =
      case AI.search(query, items) do
        {:ok, matched_ids} ->
          ai_results =
            items
            |> Enum.filter(&(&1.id in matched_ids))
            |> Enum.sort_by(fn item ->
              Enum.find_index(matched_ids, fn id -> id == item.id end) || 999
            end)

          socket
          |> assign(:ai_loading, false)
          |> assign(:ai_results, ai_results)
          |> assign(:ai_query, query)

        {:error, reason} ->
          require Logger

          Logger.error("AI search failed: #{inspect(reason)}")

          socket
          |> assign(:ai_loading, false)
          |> assign(:show_ai_modal, true)
          |> assign(:ai_modal_type, :error)
      end

    {:noreply, socket}
  end

  @impl true
  @spec handle_info({:item_deleted, String.t()}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:item_deleted, item_name}, socket) do
    socket =
      socket
      |> reset_batch_state()
      |> refresh_current_view()
      |> put_flash(:info, "Deleted: #{item_name}")

    {:noreply, socket}
  end

  @impl true
  @spec handle_info({:advance_to_next_incomplete}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:advance_to_next_incomplete}, socket) do
    socket = perform_search(socket)

    socket =
      case socket.assigns.results do
        [] ->
          socket
          |> reset_batch_state()
          |> put_flash(:info, "All items complete!")

        [next | _] = results ->
          socket
          |> assign(:selected_item_id, next.id)
          |> assign(:batch_item_ids, Enum.map(results, & &1.id))
      end

    {:noreply, socket}
  end

  @impl true
  @spec handle_info({:photo_pending, String.t(), map()}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:photo_pending, _id, photo_data}, socket) do
    send_update(ShowModal,
      id: "item-show-modal",
      pending_photo: photo_data
    )

    {:noreply, socket}
  end

  @impl true
  @spec handle_info({:photo_cleared, String.t()}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:photo_cleared, _id}, socket) do
    send_update(ShowModal,
      id: "item-show-modal",
      clear_pending_photo: true
    )

    {:noreply, socket}
  end

  @impl true
  @spec handle_info({:flash, atom(), String.t()}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:flash, kind, message}, socket) do
    Process.send_after(self(), {:clear_flash, kind}, 2000)
    {:noreply, put_flash(socket, kind, message)}
  end

  @impl true
  @spec handle_info({:clear_flash, atom()}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:clear_flash, kind}, socket) do
    {:noreply, clear_flash(socket, kind)}
  end

  @spec assign_defaults(Socket.t()) :: Socket.t()
  defp assign_defaults(socket) do
    socket
    |> assign(:view_mode, :search)
    |> assign(:query, "")
    |> assign(:results, [])
    |> assign(:show_archived, false)
    |> assign(:active_filters, [])
    |> assign(:availability_filters, [])
    |> assign(:listing_types_map, %{})
    |> assign(:items, [])
    |> assign(:sort_by, :name)
    |> assign(:sort_order, :asc)
    |> assign(:page, 1)
    |> assign(:total_count, 0)
    |> assign(:page_size, @page_size)
    |> assign(:page_title, "Items")
    |> assign(:show_ai_modal, false)
    |> assign(:ai_modal_type, nil)
    |> assign(:ai_loading, false)
    |> assign(:ai_results, nil)
    |> assign(:ai_query, nil)
    |> reset_batch_state()
  end

  @spec reset_batch_state(Socket.t()) :: Socket.t()
  defp reset_batch_state(socket) do
    socket
    |> assign(:selected_item_id, nil)
    |> assign(:start_editing, false)
    |> assign(:batch_mode, false)
    |> assign(:batch_item_ids, [])
  end

  @spec perform_search(Socket.t()) :: Socket.t()
  defp perform_search(socket) do
    {results, total_count} =
      Inventory.search_items(
        socket.assigns.current_inventory.id,
        socket.assigns.query,
        show_archived: socket.assigns.show_archived,
        filters: socket.assigns.active_filters,
        page: socket.assigns.page,
        page_size: @page_size,
        listing_types: socket.assigns.availability_filters
      )

    listing_types_map = preload_listing_types(results)

    socket
    |> assign(:results, results)
    |> assign(:total_count, total_count)
    |> assign(:listing_types_map, listing_types_map)
  end

  @spec refresh_current_view(Socket.t()) :: Socket.t()
  defp refresh_current_view(%{assigns: %{view_mode: :search}} = socket) do
    perform_search(socket)
  end

  defp refresh_current_view(%{assigns: %{view_mode: :table}} = socket) do
    load_all_items(socket)
  end

  @spec load_all_items(Socket.t()) :: Socket.t()
  defp load_all_items(socket) do
    {items, total_count} =
      Inventory.list_all_items(
        socket.assigns.current_inventory.id,
        show_archived: socket.assigns.show_archived,
        sort_by: socket.assigns.sort_by,
        sort_order: socket.assigns.sort_order,
        page: socket.assigns.page,
        page_size: @page_size,
        listing_types: socket.assigns.availability_filters
      )

    listing_types_map = preload_listing_types(items)

    socket
    |> assign(:items, items)
    |> assign(:total_count, total_count)
    |> assign(:listing_types_map, listing_types_map)
  end

  @spec toggle_filter_list([any()], any()) :: [any()]
  defp toggle_filter_list(filters, filter) do
    if filter in filters do
      List.delete(filters, filter)
    else
      [filter | filters]
    end
  end

  @spec preload_listing_types([ItemType.t()]) :: %{integer() => [String.t()]}
  defp preload_listing_types([]), do: %{}

  defp preload_listing_types(items) do
    item_ids = Enum.map(items, & &1.id)
    Marketplace.listing_types_for_items(item_ids)
  end
end
