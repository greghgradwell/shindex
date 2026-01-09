defmodule InventoryLocatorWeb.ItemLive.Components do
  @moduledoc false
  use Phoenix.Component
  use InventoryLocatorWeb, :html

  import InventoryLocatorWeb.CoreComponents

  alias Phoenix.LiveView.Rendered

  attr :items, :list, required: true

  @spec item_grid(map()) :: Rendered.t()
  def item_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <%= for item <- @items do %>
        <.item_card item={item} />
      <% end %>
    </div>
    """
  end

  attr :item, :map, required: true

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
      <p class="text-sm text-gray-600">
        {if @item.location, do: @item.location.full_code, else: "No location"}
      </p>
      <p class="text-sm">{@item.quantity} in stock</p>

      <%= if @item.archived do %>
        <span class="inline-block mt-2 px-2 py-1 bg-gray-200 text-gray-700 text-xs rounded">
          Archived
        </span>
      <% end %>
    </div>
    """
  end
end
