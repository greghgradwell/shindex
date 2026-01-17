defmodule InventoryLocatorWeb.CameraLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Inventory
  alias InventoryLocator.Media
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    inventory_id = socket.assigns.current_inventory.id

    socket =
      socket
      |> assign(:page_title, "Add Item")
      |> assign(:location_codes, Inventory.list_location_codes(inventory_id))
      |> assign(:saved_items, [])
      |> assign(:form, to_form(%{"name" => "", "location" => "", "quantity" => "1"}))
      |> assign(:show_optional, false)
      |> assign(:co_location_warning, nil)
      |> assign(:pending_photo, nil)

    {:ok, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("validate", %{"name" => name, "location" => location} = params, socket) do
    inventory_id = socket.assigns.current_inventory.id
    co_location_warning = check_co_location(inventory_id, location)

    form = to_form(params)

    socket =
      socket
      |> assign(:form, form)
      |> assign(:co_location_warning, co_location_warning)
      |> validate_required(name, location)

    {:noreply, socket}
  end

  def handle_event("toggle_optional", _params, socket) do
    {:noreply, assign(socket, :show_optional, !socket.assigns.show_optional)}
  end

  def handle_event("save", params, socket) do
    name = params["name"] || ""
    location = params["location"] || ""
    quantity = parse_quantity(params["quantity"])
    description = params["description"]
    manufacturer = params["manufacturer"]
    model = params["model"]

    if name == "" or location == "" do
      {:noreply, put_flash(socket, :error, "Name and location are required")}
    else
      case save_item_with_photo(socket, name, location, quantity, description, manufacturer, model) do
        {:ok, item, socket} ->
          socket =
            socket
            |> assign(:saved_items, [item | socket.assigns.saved_items])
            |> assign(:form, to_form(%{"name" => "", "location" => location, "quantity" => "1"}))
            |> assign(:co_location_warning, nil)
            |> assign(:pending_photo, nil)
            |> put_flash(:info, "Saved: #{item.name}")

          {:noreply, socket}

        {:error, reason, socket} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    end
  end

  # Handle messages from PhotoCapture component
  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:photo_pending, _id, photo_data}, socket) do
    {:noreply, assign(socket, :pending_photo, photo_data)}
  end

  def handle_info({:photo_cleared, _id}, socket) do
    {:noreply, assign(socket, :pending_photo, nil)}
  end

  @spec save_item_with_photo(
          Socket.t(),
          String.t(),
          String.t(),
          integer(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) ::
          {:ok, map(), Socket.t()} | {:error, term(), Socket.t()}
  defp save_item_with_photo(socket, name, location, quantity, description, manufacturer, model) do
    # Process pending photo if present
    case process_pending_photo(socket.assigns.pending_photo) do
      {:ok, photo_path} ->
        create_item(socket, name, location, quantity, description, manufacturer, model, photo_path)

      {:error, reason} ->
        {:error, reason, socket}
    end
  end

  @spec process_pending_photo(map() | nil) :: {:ok, String.t() | nil} | {:error, term()}
  defp process_pending_photo(nil), do: {:ok, nil}

  defp process_pending_photo(%{binary: binary, filename: filename}) do
    Media.process_and_save_photo(binary, filename)
  end

  @spec create_item(
          Socket.t(),
          String.t(),
          String.t(),
          integer(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) ::
          {:ok, map(), Socket.t()} | {:error, term(), Socket.t()}
  defp create_item(socket, name, location, quantity, description, manufacturer, model, photo_path) do
    inventory_id = socket.assigns.current_inventory.id

    case Inventory.ensure_location_with_code(inventory_id, location) do
      {:ok, loc} ->
        do_create(socket, name, quantity, description, manufacturer, model, photo_path, loc.id)

      {:ok, loc, _count} ->
        do_create(socket, name, quantity, description, manufacturer, model, photo_path, loc.id)

      {:error, :invalid_format} ->
        {:error, :invalid_location, socket}

      {:error, reason} ->
        {:error, reason, socket}
    end
  end

  @spec do_create(
          Socket.t(),
          String.t(),
          integer(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil,
          String.t() | nil,
          integer()
        ) ::
          {:ok, map(), Socket.t()} | {:error, term(), Socket.t()}
  defp do_create(socket, name, quantity, description, manufacturer, model, photo_path, location_id) do
    attrs = %{
      name: name,
      quantity: quantity,
      description: blank_to_nil(description),
      manufacturer: blank_to_nil(manufacturer),
      model: blank_to_nil(model),
      photo_path: photo_path,
      archived: false,
      location_id: location_id
    }

    case Inventory.create_item_type(attrs) do
      {:ok, item} ->
        {:ok, item, socket}

      {:error, changeset} ->
        {:error, changeset, socket}
    end
  end

  @spec check_co_location(integer(), String.t()) :: String.t() | nil
  defp check_co_location(_inventory_id, location) when location == "", do: nil

  defp check_co_location(inventory_id, location) do
    case Inventory.ensure_location_with_code(inventory_id, location) do
      {:ok, _location, count} when count > 0 ->
        "#{count} item(s) already at this location"

      _ ->
        nil
    end
  end

  @spec validate_required(Socket.t(), String.t(), String.t()) :: Socket.t()
  defp validate_required(socket, name, location) do
    errors =
      []
      |> maybe_add_error(name == "", "Name is required")
      |> maybe_add_error(location == "", "Location is required")

    if errors == [] do
      clear_flash(socket, :error)
    else
      socket
    end
  end

  @spec maybe_add_error([String.t()], boolean(), String.t()) :: [String.t()]
  defp maybe_add_error(errors, true, message), do: [message | errors]
  defp maybe_add_error(errors, false, _message), do: errors

  @spec parse_quantity(String.t() | nil) :: integer()
  defp parse_quantity(nil), do: 1
  defp parse_quantity(""), do: 1

  defp parse_quantity(str) do
    case Integer.parse(str) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str), do: str

  @spec format_error(term()) :: String.t()
  defp format_error(:invalid_location), do: "Invalid location format (use A-1-1)"
  defp format_error(:invalid_format), do: "Invalid location format (use A-1-1)"
  defp format_error(%Ecto.Changeset{} = cs), do: "Save failed: #{inspect(cs.errors)}"
  defp format_error(reason), do: "Error: #{inspect(reason)}"
end
