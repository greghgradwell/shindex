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
    <div class="border border-base-300 rounded-lg p-2 flex-1">
      <!-- Bin header -->
      <div class="mb-2 pb-1 border-b border-base-300">
        <span class="font-medium text-sm">Bin {@bin.code}</span>
      </div>
      <!-- Cells row -->
      <div class="flex gap-1">
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

    ~H"""
    <div
      class={[
        "aspect-square border rounded flex flex-col items-center justify-center gap-1 transition-all",
        @occupied && "border-success bg-success/10 hover:bg-success/20 cursor-pointer",
        !@occupied && "border-base-300 bg-base-100 hover:bg-base-200"
      ]}
      phx-click={@occupied && JS.push("show_quickview", value: %{location_id: @location.id})}
    >
      <!-- Cell label -->
      <span class="text-xs">{@cell.code}</span>
      <!-- Status indicator -->
      <%= if @occupied do %>
        <.icon name="hero-check-circle-solid" class="size-4 text-success" />
      <% else %>
        <button
          phx-click={JS.push("delete_location", value: %{id: @location.id})}
          class="btn btn-xs btn-ghost"
          data-confirm="Delete this empty location?"
        >
          <.icon name="hero-trash" class="size-3" />
        </button>
      <% end %>
    </div>
    """
  end

  attr :location, Location, required: true
  attr :on_close, JS, required: true

  def quickview_modal(assigns) do
    ~H"""
    <div class="modal modal-open" phx-click={@on_close} phx-key="escape">
      <div class="modal-box" phx-click-away={@on_close}>
        <h3 class="font-bold text-lg">Location {@location.full_code}</h3>

        <%= if length(@location.item_types) > 0 do %>
          <table class="table mt-4">
            <thead>
              <tr>
                <th>Item</th>
                <th>Quantity</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for item <- @location.item_types do %>
                <tr class={if item.archived, do: "opacity-50", else: ""}>
                  <td>
                    {item.name}
                    <%= if item.archived do %>
                      <span class="badge badge-sm">Archived</span>
                    <% end %>
                  </td>
                  <td>{item.quantity}</td>
                  <td>
                    <.link navigate={~p"/items/#{item.id}"} class="link">
                      View
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% else %>
          <p class="mt-4 text-gray-600">No items at this location</p>
        <% end %>

        <div class="modal-action">
          <button class="btn" phx-click={@on_close}>Close</button>
        </div>
      </div>
    </div>
    """
  end
end
