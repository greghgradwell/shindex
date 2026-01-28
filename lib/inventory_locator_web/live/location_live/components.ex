defmodule InventoryLocatorWeb.LocationLive.Components do
  @moduledoc false
  use InventoryLocatorWeb, :html

  alias InventoryLocator.Inventory.Bin
  alias InventoryLocator.Inventory.Location
  alias InventoryLocator.Inventory.Shelf
  alias Phoenix.LiveView.JS

  attr :shelf, Shelf, required: true

  def shelf_row(assigns) do
    ~H"""
    <div class="flex gap-4 items-start border-b border-base-300 pb-4">
      <!-- Shelf label (fixed width) -->
      <div class="w-32 flex-shrink-0">
        <div class="flex items-center gap-1">
          <%= if @shelf.system do %>
            <span class="font-semibold text-base-content/60">{@shelf.code}</span>
          <% else %>
            <button
              phx-click="show_rename_shelf_modal"
              phx-value-id={@shelf.id}
              class="font-semibold hover:text-primary cursor-pointer transition-colors"
              title="Click to rename shelf"
            >
              {@shelf.code}
            </button>
            <button
              phx-click="delete_shelf"
              phx-value-id={@shelf.id}
              class="btn btn-xs btn-ghost opacity-50 hover:opacity-100"
              title="Delete shelf"
              data-confirm={"Delete shelf #{@shelf.code} and all its bins?"}
            >
              <.icon name="hero-trash" class="w-3 h-3" />
            </button>
          <% end %>
        </div>
      </div>
      <!-- Bins container -->
      <div class="flex-1 flex gap-2 flex-wrap items-start">
        <%= for bin <- @shelf.bins do %>
          <.bin_segment bin={bin} shelf_id={@shelf.id} shelf_code={@shelf.code} />
        <% end %>
        <button
          :if={not @shelf.system}
          phx-click="add_bin"
          phx-value-shelf_id={@shelf.id}
          class="border border-dashed border-base-300 rounded-lg p-2 min-w-[80px] h-[80px] flex items-center justify-center text-base-content/50 hover:border-primary hover:text-primary transition-colors"
          title="Add bin"
        >
          <.icon name="hero-plus" class="w-5 h-5" />
        </button>
      </div>
    </div>
    """
  end

  attr :bin, Bin, required: true
  attr :shelf_id, :integer, required: true
  attr :shelf_code, :string, required: true

  def bin_segment(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-lg p-2 min-w-[120px] max-w-[200px]">
      <!-- Bin header -->
      <div class="mb-2 pb-1 border-b border-base-300">
        <button
          phx-click="show_rename_bin_modal"
          phx-value-id={@bin.id}
          phx-value-shelf_id={@shelf_id}
          class="font-medium text-sm hover:text-primary cursor-pointer transition-colors"
          title="Click to rename bin"
        >
          {@bin.code}
        </button>
      </div>
      <!-- Location content -->
      <.location_box
        :if={@bin.location}
        location={@bin.location}
        location_code={"#{@shelf_code}-#{@bin.code}"}
      />
    </div>
    """
  end

  attr :location, Location, required: true
  attr :location_code, :string, required: true

  def location_box(assigns) do
    active_items = Enum.reject(assigns.location.item_types || [], & &1.archived)
    occupied = active_items != []
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
          <button
            phx-click="open_item_modal"
            phx-value-id={item.id}
            class="border border-success/50 bg-success/20 hover:bg-success/30 rounded px-2 py-1 text-xs font-medium text-center transition-colors truncate"
          >
            {item.name}
          </button>
        <% end %>
      <% else %>
        <div class="flex items-center justify-between w-full">
          <span class="text-xs text-base-content/50">Empty</span>
          <button
            phx-click={JS.push("delete_location", value: %{id: @location.id})}
            class="btn btn-xs btn-ghost"
            data-confirm="Delete this empty location?"
          >
            <.icon name="hero-trash" class="size-3" />
          </button>
        </div>
      <% end %>
      <button
        phx-click="show_add_item_modal"
        phx-value-location_code={@location_code}
        class="border border-dashed border-base-300 rounded px-2 py-1 flex items-center justify-center text-base-content/50 hover:border-primary hover:text-primary transition-colors mt-1 w-full"
        title={"Add item to #{@location_code}"}
      >
        <.icon name="hero-plus" class="w-3 h-3" />
      </button>
    </div>
    """
  end
end
