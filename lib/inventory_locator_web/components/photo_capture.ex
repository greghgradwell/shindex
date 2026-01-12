defmodule InventoryLocatorWeb.Components.PhotoCapture do
  @moduledoc false
  use InventoryLocatorWeb, :live_component

  alias InventoryLocator.Media
  alias Phoenix.LiveView.Socket

  require Logger

  # Max size for base64 data URI preview (5MB binary = ~6.7MB base64)
  @max_preview_size 5_000_000

  @impl true
  @spec mount(Socket.t()) :: {:ok, Socket.t()}
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_url_input, false)
     |> assign(:fetching_url, false)
     |> assign(:photo_url, "")
     |> assign(:pending_photo, nil)
     |> assign(:error_message, nil)}
  end

  @impl true
  @spec update(map(), Socket.t()) :: {:ok, Socket.t()}
  def update(%{clear_pending: true}, socket) do
    {:ok, assign(socket, :pending_photo, nil)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:current_photo_path, fn -> nil end)
      |> assign_new(:size, fn -> :normal end)

    # Configure uploads only on initial mount
    socket =
      if Map.has_key?(socket.assigns, :uploads) do
        socket
      else
        allow_upload(socket, :photo,
          accept: ~w(.jpg .jpeg .png .webp image/*),
          max_entries: 1,
          max_file_size: 30_000_000,
          auto_upload: true
        )
      end

    {:ok, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class={photo_container_class(@size)}>
      <%!-- Error message (shown outside URL form for visibility) --%>
      <p :if={@error_message && !@show_url_input} class="text-error text-sm text-center mb-2">
        {@error_message}
      </p>

      <div
        class={drop_zone_class(@size)}
        phx-drop-target={@uploads.photo.ref}
      >
        <form id={"#{@id}-upload-form"} phx-change="photo_changed" phx-target={@myself}>
          <.live_file_input upload={@uploads.photo} class="hidden" />
        </form>

        <%!-- File upload preview --%>
        <%= for entry <- @uploads.photo.entries do %>
          <div class="relative inline-block">
            <.live_img_preview entry={entry} class={preview_class(@size)} />
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              phx-target={@myself}
              class="absolute -top-2 -right-2 btn btn-circle btn-xs btn-error"
            >
              ✕
            </button>
            <div class="mt-2 text-center">
              <div :if={not entry.done?} class="space-y-1">
                <progress class="progress progress-primary w-full" value={entry.progress} max="100" />
                <p class="text-xs text-base-content/60">
                  {if entry.progress == 0,
                    do: "Starting upload...",
                    else: "Uploading #{entry.progress}%"}
                </p>
              </div>
              <div
                :if={entry.done?}
                id={"#{@id}-upload-done"}
                phx-hook="AutoConfirmUpload"
                data-target={@myself.cid}
                class="text-success text-sm font-medium"
              >
                ✓ Processing...
              </div>
            </div>
          </div>
          <%= for err <- upload_errors(@uploads.photo, entry) do %>
            <p class="text-error text-sm mt-2">{error_to_string(err)}</p>
          <% end %>
        <% end %>

        <%!-- URL photo preview --%>
        <%= if @pending_photo && @uploads.photo.entries == [] do %>
          <div class="relative inline-block">
            <img src={@pending_photo.data_uri} class={preview_class(@size)} alt="Fetched from URL" />
            <button
              type="button"
              phx-click="cancel_pending"
              phx-target={@myself}
              class="absolute -top-2 -right-2 btn btn-circle btn-xs btn-error"
            >
              ✕
            </button>
            <div class="mt-2 text-center text-success text-sm font-medium">
              ✓ Ready (from URL)
            </div>
          </div>
        <% end %>

        <%!-- Empty state --%>
        <div :if={@uploads.photo.entries == [] && @pending_photo == nil} class="space-y-3">
          <%= if @current_photo_path do %>
            <%!-- Show existing photo --%>
            <img
              src={"/uploads/#{@current_photo_path}"}
              alt="Current photo"
              class={preview_class(@size)}
            />
            <div class="flex flex-col items-center gap-1">
              <label for={@uploads.photo.ref} class={select_button_class(@size)}>
                📷 Change Photo
              </label>
              <button
                type="button"
                phx-click="toggle_url_input"
                phx-target={@myself}
                class="btn btn-ghost btn-xs"
              >
                🌐 From URL
              </button>
            </div>
          <% else %>
            <%!-- No photo placeholder --%>
            <div class={placeholder_icon_class(@size)}>📷</div>
            <div class="text-base-content/60">Tap to capture or select photo</div>
            <div class="flex flex-col items-center gap-2">
              <label for={@uploads.photo.ref} class={select_button_class(@size)}>
                📷 Select Photo
              </label>
              <button
                type="button"
                phx-click="toggle_url_input"
                phx-target={@myself}
                class="btn btn-ghost btn-sm"
              >
                🌐 From URL
              </button>
            </div>
          <% end %>

          <%!-- URL Input --%>
          <form
            :if={@show_url_input}
            id={"#{@id}-url-form"}
            phx-change="update_url"
            phx-submit="fetch_from_url"
            phx-target={@myself}
            class="mt-4 space-y-2 w-full max-w-sm mx-auto"
          >
            <input
              type="url"
              id={"#{@id}-url-input"}
              name="photo_url"
              value={@photo_url}
              placeholder="https://example.com/image.jpg"
              class="input input-bordered w-full"
              phx-debounce="100"
              autofocus
            />
            <p :if={@error_message} class="text-error text-sm text-center">{@error_message}</p>
            <div class="flex gap-2 justify-center">
              <button
                type="submit"
                class="btn btn-primary btn-sm"
                disabled={@fetching_url or @photo_url == ""}
              >
                {if @fetching_url, do: "⏳ Fetching...", else: "Fetch"}
              </button>
              <button
                type="button"
                phx-click="cancel_url_input"
                phx-target={@myself}
                class="btn btn-ghost btn-sm"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("photo_changed", _params, socket) do
    # Just acknowledge the change - user will click "Use Photo" when ready
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    socket = cancel_upload(socket, :photo, ref)
    notify_parent({:photo_cleared, socket.assigns.id})
    {:noreply, socket}
  end

  def handle_event("cancel_pending", _params, socket) do
    notify_parent({:photo_cleared, socket.assigns.id})
    {:noreply, assign(socket, :pending_photo, nil)}
  end

  def handle_event("confirm_upload", _params, socket) do
    socket = consume_and_notify_upload(socket)
    {:noreply, socket}
  end

  def handle_event("toggle_url_input", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_url_input, not socket.assigns.show_url_input)
     |> assign(:error_message, nil)}
  end

  def handle_event("cancel_url_input", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_url_input, false)
     |> assign(:fetching_url, false)
     |> assign(:photo_url, "")
     |> assign(:error_message, nil)}
  end

  def handle_event("update_url", %{"photo_url" => url}, socket) do
    {:noreply, assign(socket, :photo_url, url)}
  end

  def handle_event("fetch_from_url", _params, socket) do
    url = socket.assigns.photo_url

    if url == "" do
      {:noreply, assign(socket, :error_message, "Please enter a URL")}
    else
      socket =
        socket
        |> assign(:fetching_url, true)
        |> assign(:error_message, nil)

      case Media.fetch_image_from_url(url) do
        {:ok, binary, filename} ->
          case create_photo_data(binary, filename) do
            {:ok, photo_data} ->
              notify_parent({:photo_pending, socket.assigns.id, photo_data})

              {:noreply,
               socket
               |> assign(:pending_photo, photo_data)
               |> assign(:show_url_input, false)
               |> assign(:fetching_url, false)
               |> assign(:photo_url, "")
               |> assign(:error_message, nil)}

            {:error, :too_large_for_preview} ->
              {:noreply,
               socket
               |> assign(:fetching_url, false)
               |> assign(:error_message, "Image too large for preview (max 5MB)")}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:fetching_url, false)
           |> assign(:error_message, format_url_error(reason))}
      end
    end
  end

  # Private Functions

  @spec consume_and_notify_upload(Socket.t()) :: Socket.t()
  defp consume_and_notify_upload(socket) do
    case socket.assigns.uploads.photo.entries do
      [entry | _] when entry.done? ->
        result =
          consume_uploaded_entry(socket, entry, fn %{path: temp_path} ->
            binary = File.read!(temp_path)
            {:ok, {binary, entry.client_name}}
          end)

        case result do
          {binary, filename} ->
            case create_photo_data(binary, filename) do
              {:ok, photo_data} ->
                notify_parent({:photo_pending, socket.assigns.id, photo_data})

                socket
                |> assign(:pending_photo, photo_data)
                |> assign(:error_message, nil)

              {:error, :too_large_for_preview} ->
                Logger.warning("Upload too large for preview: #{byte_size(binary)} bytes")
                assign(socket, :error_message, "Image too large for preview (max 5MB)")
            end

          error ->
            Logger.warning("Failed to consume upload: #{inspect(error)}")
            assign(socket, :error_message, "Failed to process upload")
        end

      _ ->
        socket
    end
  end

  @spec create_photo_data(binary(), String.t()) ::
          {:ok, %{binary: binary(), filename: String.t(), data_uri: String.t()}}
          | {:error, :too_large_for_preview}
  defp create_photo_data(binary, filename) do
    if byte_size(binary) > @max_preview_size do
      {:error, :too_large_for_preview}
    else
      data_uri = "data:image/jpeg;base64,#{Base.encode64(binary)}"
      {:ok, %{binary: binary, filename: filename, data_uri: data_uri}}
    end
  end

  @spec notify_parent(term()) :: :ok
  defp notify_parent(message) do
    send(self(), message)
    :ok
  end

  # Styling helpers

  @spec photo_container_class(atom()) :: String.t()
  defp photo_container_class(:compact), do: "relative"
  defp photo_container_class(_), do: "relative"

  @spec drop_zone_class(atom()) :: String.t()
  defp drop_zone_class(:compact) do
    "border-2 border-dashed border-base-300 rounded-lg p-4 text-center bg-base-200 cursor-pointer hover:border-primary transition-colors"
  end

  defp drop_zone_class(_) do
    "border-2 border-dashed border-base-300 rounded-xl p-6 text-center bg-base-200 cursor-pointer hover:border-primary transition-colors"
  end

  @spec preview_class(atom()) :: String.t()
  defp preview_class(:compact), do: "max-h-40 rounded-lg mx-auto"
  defp preview_class(_), do: "max-h-48 rounded-lg mx-auto"

  @spec select_button_class(atom()) :: String.t()
  defp select_button_class(:compact), do: "btn btn-primary btn-sm cursor-pointer"
  defp select_button_class(_), do: "btn btn-primary btn-lg cursor-pointer"

  @spec placeholder_icon_class(atom()) :: String.t()
  defp placeholder_icon_class(:compact), do: "text-3xl"
  defp placeholder_icon_class(_), do: "text-5xl"

  # Error formatting

  @spec error_to_string(atom()) :: String.t()
  defp error_to_string(:too_large), do: "File is too large (max 30MB)"
  defp error_to_string(:too_many_files), do: "Only one photo allowed"
  defp error_to_string(:not_accepted), do: "Invalid file type (use JPG, PNG, or WebP)"
  defp error_to_string(err), do: "Upload error: #{inspect(err)}"

  @spec format_url_error(term()) :: String.t()
  defp format_url_error(:invalid_url), do: "Invalid URL format"
  defp format_url_error(:insecure_url), do: "URL must use HTTPS"
  defp format_url_error(:forbidden_host), do: "Cannot fetch from internal or private addresses"
  defp format_url_error(:not_an_image), do: "URL does not point to an image"
  defp format_url_error(:file_too_large), do: "Image too large (max 10MB)"
  defp format_url_error({:http_error, 404}), do: "Image not found (404)"
  defp format_url_error({:http_error, status}), do: "Failed to fetch image (HTTP #{status})"
  defp format_url_error({:fetch_failed, _}), do: "Network error - could not reach URL"
end
