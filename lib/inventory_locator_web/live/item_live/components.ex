defmodule InventoryLocatorWeb.ItemLive.Components do
  @moduledoc false
  use Phoenix.Component
  use InventoryLocatorWeb, :html

  import InventoryLocatorWeb.CoreComponents

  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Rendered

  attr :items, :list, required: true
  attr :listing_types_map, :map, required: true

  @spec item_grid(map()) :: Rendered.t()
  def item_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <%= for item <- @items do %>
        <.item_card item={item} listing_types={Map.get(@listing_types_map, item.id, [])} />
      <% end %>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :listing_types, :list, required: true

  @spec item_card(map()) :: Rendered.t()
  def item_card(assigns) do
    ~H"""
    <div
      class={[
        "border rounded-lg p-4 hover:shadow-lg transition-shadow cursor-pointer",
        if(@item.archived, do: "opacity-50", else: "")
      ]}
      phx-click="open_item_modal"
      phx-value-id={@item.id}
    >
      <%= if @item.photo_path do %>
        <img
          src={"/uploads/#{@item.photo_path}"}
          alt={@item.name}
          class="w-full h-48 object-cover rounded"
        />
      <% else %>
        <div class="w-full h-48 bg-gray-200 rounded flex items-center justify-center">
          <.icon name="hero-photo" class="w-12 h-12 text-gray-400" />
        </div>
      <% end %>

      <h3 class="mt-2 font-semibold">{@item.name}</h3>
      <p :if={@item.manufacturer || @item.model} class="text-xs text-base-content/70 truncate">
        {[@item.manufacturer, @item.model] |> Enum.filter(& &1) |> Enum.join(" / ")}
      </p>
      <p class="text-sm text-gray-600">
        {if @item.location, do: @item.location.full_code, else: "No location"}
      </p>
      <p class="text-sm">{@item.quantity} in stock</p>
      <.availability_badges listing_types={@listing_types} />

      <%= if @item.archived do %>
        <span class="inline-block mt-2 px-2 py-1 bg-gray-200 text-gray-700 text-xs rounded">
          Archived
        </span>
      <% end %>
    </div>
    """
  end

  attr :query, :string, required: true
  attr :results, :list, required: true
  attr :active_filters, :list, required: true
  attr :page, :integer, required: true
  attr :total_count, :integer, required: true
  attr :page_size, :integer, required: true
  attr :listing_types_map, :map, required: true

  @spec search_view(map()) :: Rendered.t()
  def search_view(assigns) do
    ~H"""
    <div class="mt-4">
      <.form :let={f} for={%{}} phx-change="search" phx-submit="submit_search" autocomplete="off">
        <.input
          id="search-input"
          field={f[:query]}
          type="text"
          label="Search"
          placeholder="Search by name..."
          value={@query}
          phx-debounce="300"
          phx-mounted={JS.focus()}
        />
      </.form>

      <div class="mt-6 border rounded-lg p-4">
        <h3 class="font-semibold mb-3 text-sm">Filter by Missing Fields</h3>
        <div class="space-y-2">
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              phx-click="toggle_filter"
              phx-value-filter="manufacturer"
              checked={:manufacturer in @active_filters}
              class="checkbox checkbox-sm"
            />
            <span class="text-sm">Missing manufacturer</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              phx-click="toggle_filter"
              phx-value-filter="model"
              checked={:model in @active_filters}
              class="checkbox checkbox-sm"
            />
            <span class="text-sm">Missing model / part #</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              phx-click="toggle_filter"
              phx-value-filter="description"
              checked={:description in @active_filters}
              class="checkbox checkbox-sm"
            />
            <span class="text-sm">Missing description</span>
          </label>
        </div>
      </div>
    </div>

    <div class="mt-8">
      <%= cond do %>
        <% @query == "" and @active_filters == [] -> %>
          <p class="text-gray-500 text-center py-12">
            Start typing to search for items or select filters to find incomplete items
          </p>
        <% @results == [] -> %>
          <p class="text-base-content/60 text-center py-8">
            No results for "{@query}" <br />
            <span class="text-sm">Press Enter to try AI-powered search</span>
          </p>
        <% true -> %>
          <.item_grid items={@results} listing_types_map={@listing_types_map} />
          <.pagination_controls page={@page} total_count={@total_count} page_size={@page_size} />
      <% end %>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :sort_by, :atom, required: true
  attr :sort_order, :atom, required: true
  attr :page, :integer, required: true
  attr :total_count, :integer, required: true
  attr :page_size, :integer, required: true
  attr :listing_types_map, :map, required: true

  @spec table_view(map()) :: Rendered.t()
  def table_view(assigns) do
    ~H"""
    <div class="mt-6 overflow-x-auto">
      <%= if @items == [] do %>
        <p class="text-gray-500 text-center py-12">No items found</p>
      <% else %>
        <.pagination_controls page={@page} total_count={@total_count} page_size={@page_size} />
        <table class="table table-zebra w-full">
          <thead>
            <tr>
              <th class="w-16">Photo</th>
              <th phx-click="sort" phx-value-column="name" class="cursor-pointer hover:bg-base-200">
                Name <.sort_indicator column={:name} sort_by={@sort_by} sort_order={@sort_order} />
              </th>
              <th
                phx-click="sort"
                phx-value-column="manufacturer"
                class="cursor-pointer hover:bg-base-200"
              >
                Manufacturer
                <.sort_indicator column={:manufacturer} sort_by={@sort_by} sort_order={@sort_order} />
              </th>
              <th phx-click="sort" phx-value-column="model" class="cursor-pointer hover:bg-base-200">
                Model / Part #
                <.sort_indicator column={:model} sort_by={@sort_by} sort_order={@sort_order} />
              </th>
              <th
                phx-click="sort"
                phx-value-column="location"
                class="cursor-pointer hover:bg-base-200"
              >
                Location
                <.sort_indicator column={:location} sort_by={@sort_by} sort_order={@sort_order} />
              </th>
              <th>Qty</th>
              <th>Available</th>
            </tr>
          </thead>
          <tbody>
            <%= for item <- @items do %>
              <tr
                phx-click="open_item_modal"
                phx-value-id={item.id}
                class={["cursor-pointer hover:bg-base-200", if(item.archived, do: "opacity-50")]}
              >
                <td>
                  <%= if item.photo_path do %>
                    <img
                      src={"/uploads/#{item.photo_path}"}
                      class="w-12 h-12 object-cover rounded"
                    />
                  <% else %>
                    <div class="w-12 h-12 bg-base-200 rounded flex items-center justify-center">
                      <.icon name="hero-photo" class="w-6 h-6 opacity-30" />
                    </div>
                  <% end %>
                </td>
                <td class="font-medium">{item.name}</td>
                <td class="text-base-content/70">{item.manufacturer || "—"}</td>
                <td class="text-base-content/70">{item.model || "—"}</td>
                <td class="font-mono text-sm">
                  {if item.location, do: item.location.full_code, else: "—"}
                </td>
                <td>{item.quantity}</td>
                <td>
                  <.availability_badges listing_types={Map.get(@listing_types_map, item.id, [])} />
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <.pagination_controls page={@page} total_count={@total_count} page_size={@page_size} />
      <% end %>
    </div>
    """
  end

  attr :page, :integer, required: true
  attr :total_count, :integer, required: true
  attr :page_size, :integer, required: true

  @spec pagination_controls(map()) :: Rendered.t()
  def pagination_controls(assigns) do
    assigns = assign(assigns, :total_pages, max(ceil(assigns.total_count / assigns.page_size), 1))

    ~H"""
    <div :if={@total_pages > 1} class="flex items-center justify-center gap-2 mt-6">
      <button
        class="btn btn-sm btn-ghost"
        phx-click="change_page"
        phx-value-page={@page - 1}
        disabled={@page <= 1}
      >
        <.icon name="hero-chevron-left" class="w-4 h-4" />
      </button>
      <span class="text-sm">Page {@page} of {@total_pages}</span>
      <button
        class="btn btn-sm btn-ghost"
        phx-click="change_page"
        phx-value-page={@page + 1}
        disabled={@page >= @total_pages}
      >
        <.icon name="hero-chevron-right" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  attr :column, :atom, required: true
  attr :sort_by, :atom, required: true
  attr :sort_order, :atom, required: true

  @spec sort_indicator(map()) :: Rendered.t()
  def sort_indicator(assigns) do
    ~H"""
    <%= if @column == @sort_by do %>
      <span class="ml-1 text-primary">
        {if @sort_order == :asc, do: "▲", else: "▼"}
      </span>
    <% end %>
    """
  end

  attr :listing_types, :list, required: true

  @spec availability_badges(map()) :: Rendered.t()
  def availability_badges(assigns) do
    ~H"""
    <div :if={@listing_types != []} class="flex flex-wrap gap-1 mt-1">
      <span :if={"borrow" in @listing_types} class="badge badge-xs badge-info">Borrow</span>
      <span :if={"lease" in @listing_types} class="badge badge-xs badge-warning">Lease</span>
      <span :if={"sale" in @listing_types} class="badge badge-xs badge-success">Buy</span>
    </div>
    """
  end
end
