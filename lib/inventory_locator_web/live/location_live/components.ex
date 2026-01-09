defmodule InventoryLocatorWeb.LocationLive.Components do
  use InventoryLocatorWeb, :html

  alias InventoryLocator.Inventory.{Shelf, Bin, Cell, Location}
  alias Phoenix.LiveView.JS

  attr :shelf, Shelf, required: true

  def shelf_row(assigns) do
    ~H"""
    <div class="flex gap-4 items-start border-b border-base-300 pb-4">
      <!-- Shelf label (fixed width) -->
      <div class="w-32 flex-shrink-0">
        <h3 class="font-semibold">{@shelf.code}</h3>
        <p class="text-sm text-base-content/70">{@shelf.name}</p>
      </div>
      <!-- Bins container -->
      <div class="flex-1 flex gap-2">
        <%= for bin <- @shelf.bins do %>
          <.bin_segment bin={bin} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :bin, Bin, required: true

  def bin_segment(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-lg p-2 min-w-[120px] max-w-[200px]">
      <!-- Bin header -->
      <div class="mb-2 pb-1 border-b border-base-300">
        <span class="font-medium text-sm">Bin {@bin.code}</span>
      </div>
      <!-- Cells column (stacked vertically with dividers) -->
      <div class="flex flex-col divide-y-2 divide-base-content/20">
        <%= for cell <- @bin.cells do %>
          <%= if cell.location do %>
            <.cell_box cell={cell} location={cell.location} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :cell, Cell, required: true
  attr :location, Location, required: true

  def cell_box(assigns) do
    active_items = Enum.reject(assigns.location.item_types || [], & &1.archived)
    occupied = length(active_items) > 0
    assigns = assign(assigns, :occupied, occupied)
    assigns = assign(assigns, :active_items, active_items)

    ~H"""
    <div class={[
      "flex flex-col gap-1 min-h-12 py-2",
      @occupied && "px-1",
      !@occupied &&
        "bg-base-100 rounded items-center justify-center px-1"
    ]}>
      <%= if @occupied do %>
        <%= for item <- @active_items do %>
          <.link
            navigate={~p"/items/#{item.id}"}
            class="border border-success/50 bg-success/20 hover:bg-success/30 rounded px-2 py-1 text-xs font-medium text-center transition-colors truncate"
          >
            {item.name}
          </.link>
        <% end %>
      <% else %>
        <div class="flex items-center justify-between w-full">
          <span class="text-xs text-base-content/50">{@cell.code}</span>
          <button
            phx-click={JS.push("delete_location", value: %{id: @location.id})}
            class="btn btn-xs btn-ghost"
            data-confirm="Delete this empty location?"
          >
            <.icon name="hero-trash" class="size-3" />
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
