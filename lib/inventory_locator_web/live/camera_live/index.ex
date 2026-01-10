defmodule InventoryLocatorWeb.CameraLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Inventory
  alias InventoryLocator.Media
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.UploadConfig

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Add Item")
      |> assign(:location_codes, Inventory.list_location_codes())
      |> assign(:saved_items, [])
      |> assign(:form, to_form(%{"name" => "", "location" => "", "quantity" => "1"}))
      |> assign(:show_optional, false)
      |> assign(:co_location_warning, nil)
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .webp image/*),
        max_entries: 1,
        max_file_size: 30_000_000,
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("validate", %{"name" => name, "location" => location} = params, socket) do
    co_location_warning = check_co_location(location)

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
            |> put_flash(:info, "Saved: #{item.name}")

          {:noreply, socket}

        {:error, reason, socket} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
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
    photo_result = consume_uploaded_photo(socket)

    case photo_result do
      {:ok, photo_path, socket} ->
        create_item(socket, name, location, quantity, description, manufacturer, model, photo_path)

      {:error, reason, socket} ->
        {:error, reason, socket}
    end
  end

  @spec consume_uploaded_photo(Socket.t()) :: {:ok, String.t() | nil, Socket.t()} | {:error, term(), Socket.t()}
  defp consume_uploaded_photo(socket) do
    case socket.assigns.uploads.photo.entries do
      [] ->
        {:ok, nil, socket}

      [entry | _] ->
        if entry.done? do
          result =
            consume_uploaded_entry(socket, entry, fn %{path: temp_path} ->
              binary = File.read!(temp_path)
              Media.process_and_save_photo(binary, entry.client_name)
            end)

          case result do
            filename when is_binary(filename) ->
              {:ok, filename, socket}

            {:error, reason} ->
              {:error, reason, socket}
          end
        else
          {:error, :upload_in_progress, socket}
        end
    end
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
    case Inventory.ensure_location_with_code(location) do
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

  @spec check_co_location(String.t()) :: String.t() | nil
  defp check_co_location(location) when location == "", do: nil

  defp check_co_location(location) do
    case Inventory.ensure_location_with_code(location) do
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
  defp format_error(:upload_in_progress), do: "Photo still uploading, please wait..."
  defp format_error(%Ecto.Changeset{} = cs), do: "Save failed: #{inspect(cs.errors)}"
  defp format_error(reason), do: "Error: #{inspect(reason)}"

  @spec error_to_string(atom()) :: String.t()
  def error_to_string(:too_large), do: "File is too large (max 30MB)"
  def error_to_string(:too_many_files), do: "Only one photo allowed"
  def error_to_string(:not_accepted), do: "Invalid file type (use JPG, PNG, or WebP)"
  def error_to_string(err), do: "Upload error: #{inspect(err)}"

  @spec upload_in_progress?(UploadConfig.t()) :: boolean()
  def upload_in_progress?(upload_config) do
    Enum.any?(upload_config.entries, fn entry -> not entry.done? end)
  end

  @spec upload_complete?(UploadConfig.t()) :: boolean()
  def upload_complete?(upload_config) do
    upload_config.entries != [] and Enum.all?(upload_config.entries, fn entry -> entry.done? end)
  end
end
