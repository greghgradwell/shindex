defmodule InventoryLocatorWeb.Components.GhostAutocomplete do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.HTML.FormField

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :suggestions, :list, required: true
  attr :placeholder, :string, default: ""
  attr :label, :string, default: nil
  attr :class, :string, default: nil
  attr :required, :boolean, default: false
  attr :autofocus, :boolean, default: false
  attr :field, FormField, default: nil

  @spec ghost_autocomplete(map()) :: Phoenix.LiveView.Rendered.t()
  def ghost_autocomplete(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil)
    |> assign_new(:id, fn -> field.id end)
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value || "" end)
    |> ghost_autocomplete()
  end

  def ghost_autocomplete(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <div
          id={@id <> "-container"}
          phx-hook="GhostAutocomplete"
          data-suggestions={Jason.encode!(@suggestions)}
          class="relative"
        >
          <input
            type="text"
            data-ghost-input
            id={@id}
            name={@name}
            value={@value}
            placeholder={@placeholder}
            required={@required}
            autofocus={@autofocus}
            class={@class || "w-full input font-mono"}
            style="background: transparent;"
            autocomplete="off"
          />
          <div
            class="absolute inset-0 pointer-events-none flex items-center px-4"
            aria-hidden="true"
          >
            <span data-ghost-spacer class="font-mono opacity-0">{@value}</span><span
              data-ghost-text
              class="font-mono text-base-content/40"
            ></span>
          </div>
        </div>
      </label>
    </div>
    """
  end
end
