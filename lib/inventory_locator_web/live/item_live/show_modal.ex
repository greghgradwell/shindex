defmodule InventoryLocatorWeb.ItemLive.ShowModal do
  @moduledoc false
  use InventoryLocatorWeb, :live_component

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.ItemType
  alias InventoryLocator.Inventory.Location
  alias InventoryLocator.Media
  alias Phoenix.LiveView.Socket

  require Logger

  @accepted_document_types ~w(.pdf .png .jpg .jpeg)

  @impl true
  @spec update(map(), Socket.t()) :: {:ok, Socket.t()}
  def update(%{pending_photo: photo_data}, socket) do
    {:ok, assign(socket, :pending_photo, photo_data)}
  end

  def update(%{clear_pending_photo: true}, socket) do
    {:ok, assign(socket, :pending_photo, nil)}
  end

  def update(%{item_id: item_id, current_inventory: current_inventory} = assigns, socket) do
    inventory_id = current_inventory.id
    item = Inventory.get_item_type_with_location!(item_id)
    location_codes = Inventory.list_location_codes(inventory_id)
    project_names = Inventory.list_project_names(inventory_id)
    installations = Inventory.list_installations_for_item(item)
    installed_quantity = Enum.sum(Enum.map(installations, & &1.quantity))
    documents = Media.list_documents(item_id)

    # Batch mode: auto-enter edit mode for efficient completion
    batch_mode = Map.get(assigns, :batch_mode, false)
    editing = batch_mode
    edit_changeset = if editing, do: ItemType.changeset(item, %{})

    # Configure document uploads only on initial mount
    socket =
      if Map.has_key?(socket.assigns, :uploads) do
        socket
      else
        allow_upload(socket, :document,
          accept: @accepted_document_types,
          max_entries: 1,
          max_file_size: Media.max_document_size(),
          auto_upload: true
        )
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:item, item)
     |> assign(:documents, documents)
     |> assign(:show_restore_modal, false)
     |> assign(:show_archive_quantity_modal, false)
     |> assign(:show_delete_modal, false)
     |> assign(:editing, editing)
     |> assign(:moving, false)
     |> assign(:installing, false)
     |> assign(:edit_changeset, edit_changeset)
     |> assign(:location_codes, location_codes)
     |> assign(:project_names, project_names)
     |> assign(:installations, installations)
     |> assign(:installed_quantity, installed_quantity)
     |> assign(:pending_restore_quantity, nil)
     |> assign(:location_warning, nil)
     |> assign(:location_error, nil)
     |> assign(:move_location_warning, nil)
     |> assign(:move_location_error, nil)
     |> assign(:batch_mode, batch_mode)
     |> assign(:batch_total, Map.get(assigns, :batch_total, 0))
     |> assign_new(:pending_photo, fn -> nil end)
     |> assign_new(:show_document_url_input, fn -> false end)
     |> assign_new(:document_url, fn -> "" end)
     |> assign_new(:fetching_document_url, fn -> false end)
     |> assign_new(:max_document_size_mb, fn -> div(Media.max_document_size(), 1024 * 1024) end)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("close_modal", _params, socket) do
    # Don't close if a nested modal is open (clicks inside nested modals trigger parent's click-away)
    if socket.assigns.show_delete_modal or
         socket.assigns.show_restore_modal or
         socket.assigns.show_archive_quantity_modal do
      {:noreply, socket}
    else
      send(self(), {:close_item_modal})
      {:noreply, socket}
    end
  end

  def handle_event("increment_quantity", _params, socket) do
    item = socket.assigns.item
    new_quantity = item.quantity + 1

    case Inventory.update_item_type(item, %{quantity: new_quantity}) do
      {:ok, _updated_item} ->
        {:noreply,
         socket
         |> refresh_item_data()
         |> notify_flash(:info, "Quantity updated")}

      {:error, changeset} ->
        Logger.warning("Failed to update quantity: #{inspect(changeset.errors)}")
        {:noreply, notify_flash(socket, :error, "Failed to update quantity")}
    end
  end

  def handle_event("decrement_quantity", _params, socket) do
    item = socket.assigns.item
    new_quantity = item.quantity - 1

    cond do
      new_quantity < 0 ->
        {:noreply, socket}

      new_quantity == 0 ->
        {:noreply, assign(socket, :show_archive_quantity_modal, true)}

      true ->
        case Inventory.update_item_type(item, %{quantity: new_quantity}) do
          {:ok, _updated_item} ->
            {:noreply,
             socket
             |> refresh_item_data()
             |> notify_flash(:info, "Quantity updated")}

          {:error, changeset} ->
            Logger.warning("Failed to update quantity: #{inspect(changeset.errors)}")
            {:noreply, notify_flash(socket, :error, "Failed to update quantity")}
        end
    end
  end

  def handle_event("archive", _params, socket) do
    item = socket.assigns.item

    case Inventory.archive_item_type(item) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> notify_flash(:info, "Item archived. Location is now available for reuse.")}

      {:error, changeset} ->
        Logger.warning("Failed to archive item: #{inspect(changeset.errors)}")
        {:noreply, notify_flash(socket, :error, "Failed to archive item")}
    end
  end

  def handle_event("show_restore_modal", _params, socket) do
    {:noreply, assign(socket, :show_restore_modal, true)}
  end

  def handle_event("close_restore_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_restore_modal, false)
     |> assign(:pending_restore_quantity, nil)
     |> assign(:location_warning, nil)
     |> assign(:location_error, nil)}
  end

  def handle_event("confirm_archive_from_quantity", _params, socket) do
    item = socket.assigns.item

    case Inventory.archive_item_type(item) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> assign(:show_archive_quantity_modal, false)
         |> notify_flash(:info, "Item archived. Location is now available for reuse.")}

      {:error, changeset} ->
        Logger.warning("Failed to archive item: #{inspect(changeset.errors)}")

        {:noreply,
         socket
         |> assign(:show_archive_quantity_modal, false)
         |> notify_flash(:error, "Failed to archive item")}
    end
  end

  def handle_event("cancel_archive_from_quantity", _params, socket) do
    {:noreply, assign(socket, :show_archive_quantity_modal, false)}
  end

  def handle_event("restore", %{"location_code" => location_code, "quantity" => qty_str}, socket) do
    item = socket.assigns.item
    quantity = String.to_integer(qty_str)
    inventory_id = socket.assigns.current_inventory.id

    case Inventory.validate_location_code(inventory_id, location_code) do
      {:ok, :exists, location} ->
        do_restore(socket, item, location, quantity, location_code)

      {:ok, :exists_occupied, location, _item_count} ->
        do_restore(socket, item, location, quantity, location_code)

      {:error, :invalid_format} ->
        {:noreply, assign(socket, :location_error, "Invalid format. Use SHELF-BIN (e.g., A-1)")}

      {:error, :shelf_not_found, shelf_code} ->
        {:noreply,
         assign(socket, :location_error, "Shelf '#{shelf_code}' doesn't exist. Create it on the Locations page.")}

      {:error, :bin_not_found, shelf_code, bin_code} ->
        {:noreply,
         assign(
           socket,
           :location_error,
           "Bin #{bin_code} doesn't exist on shelf #{shelf_code}. Add it on the Locations page."
         )}
    end
  end

  def handle_event("validate_location", %{"location_code" => code}, socket) do
    if code == "" do
      {:noreply,
       socket
       |> assign(:location_warning, nil)
       |> assign(:location_error, nil)}
    else
      inventory_id = socket.assigns.current_inventory.id

      case Inventory.validate_location_code(inventory_id, code) do
        {:ok, :exists, _location} ->
          {:noreply,
           socket
           |> assign(:location_warning, nil)
           |> assign(:location_error, nil)}

        {:ok, :exists_occupied, _location, item_count} ->
          {:noreply,
           socket
           |> assign(:location_warning, %{code: code, count: item_count})
           |> assign(:location_error, nil)}

        {:error, :invalid_format} ->
          {:noreply,
           socket
           |> assign(:location_warning, nil)
           |> assign(:location_error, "Invalid format. Use SHELF-BIN (e.g., A-1)")}

        {:error, :shelf_not_found, shelf_code} ->
          {:noreply,
           socket
           |> assign(:location_warning, nil)
           |> assign(:location_error, "Shelf '#{shelf_code}' doesn't exist. Create it on the Locations page.")}

        {:error, :bin_not_found, shelf_code, bin_code} ->
          {:noreply,
           socket
           |> assign(:location_warning, nil)
           |> assign(
             :location_error,
             "Bin #{bin_code} doesn't exist on shelf #{shelf_code}. Add it on the Locations page."
           )}
      end
    end
  end

  def handle_event("update_quantity", %{"quantity" => qty_str}, socket) do
    item = socket.assigns.item

    case Integer.parse(qty_str) do
      {0, _} ->
        {:noreply, assign(socket, :show_archive_quantity_modal, true)}

      {quantity, _} when quantity > 0 ->
        case Inventory.update_item_type(item, %{quantity: quantity}) do
          {:ok, _updated_item} ->
            {:noreply,
             socket
             |> refresh_item_data()
             |> notify_flash(:info, "Quantity updated")}

          {:error, changeset} ->
            Logger.warning("Failed to update quantity: #{inspect(changeset.errors)}")
            {:noreply, notify_flash(socket, :error, "Failed to update quantity")}
        end

      invalid_input ->
        Logger.warning("Invalid quantity input: #{inspect(invalid_input)}")
        {:noreply, notify_flash(socket, :error, "Invalid quantity")}
    end
  end

  def handle_event("toggle_edit", _params, socket) do
    item = socket.assigns.item
    changeset = ItemType.changeset(item, %{})

    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:edit_changeset, changeset)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, false)
     |> assign(:edit_changeset, nil)
     |> assign(:pending_photo, nil)}
  end

  def handle_event("update_item_details", params, socket) do
    item = socket.assigns.item

    # Form params are nested under "item_type" when using for={changeset}
    item_params = params["item_type"] || params

    # Process pending photo if present
    case process_pending_photo(socket.assigns.pending_photo) do
      {:ok, photo_path} ->
        attrs = %{
          name: Map.get(item_params, "name", item.name),
          manufacturer: Map.get(item_params, "manufacturer", ""),
          model: Map.get(item_params, "model", ""),
          description: Map.get(item_params, "description", ""),
          source_url: Map.get(item_params, "source_url", "")
        }

        # Add photo_path only if a new photo was uploaded
        attrs = if photo_path, do: Map.put(attrs, :photo_path, photo_path), else: attrs

        case Inventory.update_item_type(item, attrs) do
          {:ok, _updated_item} ->
            # In batch mode, advance to next incomplete item
            if socket.assigns.batch_mode do
              send(self(), {:advance_to_next_incomplete})
            end

            {:noreply,
             socket
             |> refresh_item_data()
             |> assign(:editing, false)
             |> assign(:edit_changeset, nil)
             |> assign(:pending_photo, nil)
             |> notify_flash(:info, "Item details updated")}

          {:error, changeset} ->
            Logger.warning("Failed to update item details: #{inspect(changeset.errors)}")
            {:noreply, notify_flash(socket, :error, "Failed to update item details")}
        end

      {:error, reason} ->
        Logger.warning("Failed to process photo: #{inspect(reason)}")
        {:noreply, notify_flash(socket, :error, "Failed to save photo")}
    end
  end

  def handle_event("toggle_move", _params, socket) do
    {:noreply, assign(socket, :moving, true)}
  end

  def handle_event("cancel_move", _params, socket) do
    {:noreply,
     socket
     |> assign(:moving, false)
     |> assign(:move_location_warning, nil)
     |> assign(:move_location_error, nil)}
  end

  def handle_event("validate_move_location", %{"location_code" => code}, socket) do
    if code == "" do
      {:noreply,
       socket
       |> assign(:move_location_warning, nil)
       |> assign(:move_location_error, nil)}
    else
      inventory_id = socket.assigns.current_inventory.id

      case Inventory.validate_location_code(inventory_id, code) do
        {:ok, :exists, _location} ->
          {:noreply,
           socket
           |> assign(:move_location_warning, nil)
           |> assign(:move_location_error, nil)}

        {:ok, :exists_occupied, _location, item_count} ->
          {:noreply,
           socket
           |> assign(:move_location_warning, %{code: code, count: item_count})
           |> assign(:move_location_error, nil)}

        {:error, :invalid_format} ->
          {:noreply,
           socket
           |> assign(:move_location_warning, nil)
           |> assign(:move_location_error, "Invalid format. Use SHELF-BIN (e.g., A-1)")}

        {:error, :shelf_not_found, shelf_code} ->
          {:noreply,
           socket
           |> assign(:move_location_warning, nil)
           |> assign(:move_location_error, "Shelf '#{shelf_code}' doesn't exist. Create it on the Locations page.")}

        {:error, :bin_not_found, shelf_code, bin_code} ->
          {:noreply,
           socket
           |> assign(:move_location_warning, nil)
           |> assign(
             :move_location_error,
             "Bin #{bin_code} doesn't exist on shelf #{shelf_code}. Add it on the Locations page."
           )}
      end
    end
  end

  def handle_event("move_to_location", %{"location_code" => location_code}, socket) do
    item = socket.assigns.item
    inventory_id = socket.assigns.current_inventory.id

    case Inventory.validate_location_code(inventory_id, location_code) do
      {:ok, :exists, location} ->
        do_move(socket, item, location, location_code)

      {:ok, :exists_occupied, location, _item_count} ->
        do_move(socket, item, location, location_code)

      {:error, :invalid_format} ->
        {:noreply, assign(socket, :move_location_error, "Invalid format. Use SHELF-BIN (e.g., A-1)")}

      {:error, :shelf_not_found, shelf_code} ->
        {:noreply,
         assign(socket, :move_location_error, "Shelf '#{shelf_code}' doesn't exist. Create it on the Locations page.")}

      {:error, :bin_not_found, shelf_code, bin_code} ->
        {:noreply,
         assign(
           socket,
           :move_location_error,
           "Bin #{bin_code} doesn't exist on shelf #{shelf_code}. Add it on the Locations page."
         )}
    end
  end

  def handle_event("ghost_value_changed", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_photo_only", _params, socket) do
    case process_pending_photo(socket.assigns.pending_photo) do
      {:ok, nil} ->
        {:noreply, notify_flash(socket, :error, "No photo to save")}

      {:ok, photo_path} ->
        item = socket.assigns.item

        case Inventory.update_item_type(item, %{photo_path: photo_path}) do
          {:ok, updated_item} ->
            updated_item = Inventory.get_item_type_with_location!(updated_item.id)

            # Clear the PhotoCapture component's internal pending state
            send_update(InventoryLocatorWeb.Components.PhotoCapture,
              id: "modal-photo-capture",
              clear_pending: true
            )

            {:noreply,
             socket
             |> assign(:item, updated_item)
             |> assign(:pending_photo, nil)
             |> notify_flash(:info, "Photo saved")}

          {:error, changeset} ->
            Logger.warning("Failed to save photo: #{inspect(changeset.errors)}")
            {:noreply, notify_flash(socket, :error, "Failed to save photo")}
        end

      {:error, reason} ->
        Logger.warning("Failed to process photo: #{inspect(reason)}")
        {:noreply, notify_flash(socket, :error, "Failed to save photo")}
    end
  end

  def handle_event("cancel_pending_photo", _params, socket) do
    {:noreply, assign(socket, :pending_photo, nil)}
  end

  def handle_event("document_changed", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_document_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :document, ref)}
  end

  def handle_event("save_document", _params, socket) do
    item = socket.assigns.item

    case socket.assigns.uploads.document.entries do
      [entry | _] when entry.done? ->
        result =
          consume_uploaded_entry(socket, entry, fn %{path: temp_path} ->
            case File.read(temp_path) do
              {:ok, binary} -> {:ok, {binary, entry.client_name}}
              {:error, reason} -> {:ok, {:file_error, reason}}
            end
          end)

        case result do
          {binary, filename} when is_binary(binary) ->
            case Media.save_document_file(binary, filename) do
              {:ok, storage_path, content_type, size_bytes} ->
                case Media.create_document(item.id, %{
                       filename: filename,
                       storage_path: storage_path,
                       content_type: content_type,
                       size_bytes: size_bytes
                     }) do
                  {:ok, _document} ->
                    documents = Media.list_documents(item.id)

                    {:noreply,
                     socket
                     |> assign(:documents, documents)
                     |> notify_flash(:info, "Document uploaded")}

                  {:error, changeset} ->
                    {:noreply, notify_flash(socket, :error, format_changeset_errors(changeset))}
                end

              {:error, :invalid_type} ->
                {:noreply, notify_flash(socket, :error, "Invalid file type. Use PDF, PNG, or JPEG.")}

              {:error, :file_too_large} ->
                max_mb = div(Media.max_document_size(), 1024 * 1024)
                {:noreply, notify_flash(socket, :error, "File too large (max #{max_mb}MB)")}

              {:error, _reason} ->
                {:noreply, notify_flash(socket, :error, "Failed to save document file")}
            end

          {:file_error, reason} ->
            Logger.warning("Failed to read uploaded file: #{inspect(reason)}")
            {:noreply, notify_flash(socket, :error, "Failed to read uploaded file")}

          other ->
            Logger.warning("Unexpected upload result: #{inspect(other)}")
            {:noreply, notify_flash(socket, :error, "Failed to process upload")}
        end

      _no_completed_upload ->
        # No action needed - upload may be empty or still in progress
        {:noreply, socket}
    end
  end

  def handle_event("delete_document", %{"document_id" => document_id}, socket) do
    document_id = if is_binary(document_id), do: String.to_integer(document_id), else: document_id
    document = Media.get_document!(document_id)

    case Media.delete_document(document) do
      {:ok, _deleted} ->
        documents = Media.list_documents(socket.assigns.item.id)

        {:noreply,
         socket
         |> assign(:documents, documents)
         |> notify_flash(:info, "Document deleted")}

      {:error, _} ->
        {:noreply, notify_flash(socket, :error, "Failed to delete document")}
    end
  end

  def handle_event("toggle_document_url_input", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_document_url_input, not socket.assigns.show_document_url_input)
     |> assign(:document_url, "")}
  end

  def handle_event("cancel_document_url_input", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_document_url_input, false)
     |> assign(:document_url, "")
     |> assign(:fetching_document_url, false)}
  end

  def handle_event("update_document_url", %{"document_url" => url}, socket) do
    {:noreply, assign(socket, :document_url, url)}
  end

  def handle_event("fetch_document_from_url", _params, socket) do
    url = socket.assigns.document_url
    item = socket.assigns.item

    if url == "" do
      {:noreply, notify_flash(socket, :error, "Please enter a URL")}
    else
      socket = assign(socket, :fetching_document_url, true)

      case Media.fetch_document_from_url(url) do
        {:ok, binary, filename, content_type} ->
          case Media.save_document_file(binary, filename) do
            {:ok, storage_path, _content_type, size_bytes} ->
              case Media.create_document(item.id, %{
                     filename: filename,
                     storage_path: storage_path,
                     content_type: content_type,
                     size_bytes: size_bytes
                   }) do
                {:ok, _document} ->
                  documents = Media.list_documents(item.id)

                  {:noreply,
                   socket
                   |> assign(:documents, documents)
                   |> assign(:show_document_url_input, false)
                   |> assign(:document_url, "")
                   |> assign(:fetching_document_url, false)
                   |> notify_flash(:info, "Document uploaded from URL")}

                {:error, changeset} ->
                  {:noreply,
                   socket
                   |> assign(:fetching_document_url, false)
                   |> notify_flash(:error, format_changeset_errors(changeset))}
              end

            {:error, :invalid_type} ->
              {:noreply,
               socket
               |> assign(:fetching_document_url, false)
               |> notify_flash(:error, "Invalid file type. Use PDF, PNG, or JPEG.")}

            {:error, :file_too_large} ->
              max_mb = div(Media.max_document_size(), 1024 * 1024)

              {:noreply,
               socket
               |> assign(:fetching_document_url, false)
               |> notify_flash(:error, "File too large (max #{max_mb}MB)")}

            {:error, _reason} ->
              {:noreply,
               socket
               |> assign(:fetching_document_url, false)
               |> notify_flash(:error, "Failed to save document file")}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:fetching_document_url, false)
           |> notify_flash(:error, format_document_url_error(reason))}
      end
    end
  end

  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  def handle_event("hide_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  def handle_event("delete", _params, socket) do
    item = socket.assigns.item

    case Inventory.delete_item_type(item) do
      {:ok, _} ->
        send(self(), {:item_deleted, item.name})
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, notify_flash(socket, :error, "Failed to delete item")}
    end
  end

  def handle_event("toggle_install", _params, socket) do
    {:noreply, assign(socket, :installing, true)}
  end

  def handle_event("cancel_install", _params, socket) do
    {:noreply, assign(socket, :installing, false)}
  end

  def handle_event("install_item", %{"project_name" => project_name, "quantity" => qty_str}, socket) do
    item = socket.assigns.item

    case Integer.parse(qty_str) do
      {quantity, _} when quantity > 0 ->
        case Inventory.install_item(item, project_name, quantity) do
          {:ok, _installation, updated_item} ->
            message =
              if updated_item.archived do
                "Installed #{quantity} in #{String.upcase(project_name)}. Item archived (none left in stock)."
              else
                "Installed #{quantity} in #{String.upcase(project_name)}"
              end

            {:noreply,
             socket
             |> refresh_item_data()
             |> assign(:installing, false)
             |> notify_flash(:info, message)}

          {:error, :insufficient_quantity} ->
            {:noreply, notify_flash(socket, :error, "Not enough in stock")}

          {:error, :archived} ->
            {:noreply, notify_flash(socket, :error, "Cannot install from archived item")}

          {:error, _changeset} ->
            {:noreply, notify_flash(socket, :error, "Failed to install item")}
        end

      invalid_input ->
        Logger.warning("Invalid install quantity input: #{inspect(invalid_input)}")
        {:noreply, notify_flash(socket, :error, "Invalid quantity")}
    end
  end

  def handle_event("increment_installation", %{"installation_id" => id_str}, socket) do
    installation_id = String.to_integer(id_str)
    installation = Enum.find(socket.assigns.installations, &(&1.id == installation_id))
    item = socket.assigns.item

    cond do
      is_nil(installation) ->
        {:noreply, notify_flash(socket, :error, "Installation not found")}

      item.archived ->
        {:noreply, notify_flash(socket, :error, "Cannot add to archived item")}

      item.quantity < 1 ->
        {:noreply, notify_flash(socket, :error, "No stock available")}

      true ->
        case Inventory.install_item(item, installation.project_name, 1) do
          {:ok, _installation, _updated_item} ->
            {:noreply,
             socket
             |> refresh_item_data()
             |> notify_flash(:info, "Added 1 to #{installation.project_name}")}

          {:error, _} ->
            {:noreply, notify_flash(socket, :error, "Failed to add to installation")}
        end
    end
  end

  def handle_event("decrement_installation", %{"installation_id" => id_str}, socket) do
    do_uninstall(socket, id_str, 1)
  end

  def handle_event("uninstall_item", %{"installation_id" => id_str}, socket) do
    installation_id = String.to_integer(id_str)
    installation = Enum.find(socket.assigns.installations, &(&1.id == installation_id))

    if installation do
      do_uninstall(socket, id_str, installation.quantity)
    else
      {:noreply, notify_flash(socket, :error, "Installation not found")}
    end
  end

  @spec do_uninstall(Socket.t(), String.t(), pos_integer()) :: {:noreply, Socket.t()}
  defp do_uninstall(socket, id_str, quantity) do
    installation_id = String.to_integer(id_str)
    installation = Enum.find(socket.assigns.installations, &(&1.id == installation_id))

    if installation do
      case Inventory.uninstall_item(installation, quantity) do
        {:ok, :returned_to_stock, _updated_item} ->
          {:noreply,
           socket
           |> refresh_item_data()
           |> notify_flash(:info, "Returned #{quantity} to stock from #{installation.project_name}")}

        {:ok, :needs_restore, restore_quantity} ->
          {:noreply,
           socket
           |> assign(:pending_restore_quantity, restore_quantity)
           |> assign(:show_restore_modal, true)
           |> refresh_item_data()
           |> notify_flash(
             :info,
             "#{restore_quantity} removed from #{installation.project_name}. Choose a location to restore."
           )}

        {:error, _} ->
          {:noreply, notify_flash(socket, :error, "Failed to remove installation")}
      end
    else
      {:noreply, notify_flash(socket, :error, "Installation not found")}
    end
  end

  @spec refresh_item_data(Socket.t()) :: Socket.t()
  defp refresh_item_data(socket) do
    inventory_id = socket.assigns.current_inventory.id
    item = Inventory.get_item_type_with_location!(socket.assigns.item.id)
    installations = Inventory.list_installations_for_item(item)
    installed_quantity = Enum.sum(Enum.map(installations, & &1.quantity))
    project_names = Inventory.list_project_names(inventory_id)

    socket
    |> assign(:item, item)
    |> assign(:installations, installations)
    |> assign(:installed_quantity, installed_quantity)
    |> assign(:project_names, project_names)
  end

  @spec do_move(Socket.t(), ItemType.t(), Location.t(), String.t()) ::
          {:noreply, Socket.t()}
  defp do_move(socket, item, location, location_code) do
    case Inventory.update_item_type(item, %{location_id: location.id}) do
      {:ok, updated_item} ->
        updated_item = Inventory.get_item_type_with_location!(updated_item.id)

        {:noreply,
         socket
         |> assign(:item, updated_item)
         |> assign(:moving, false)
         |> assign(:move_location_warning, nil)
         |> notify_flash(:info, "Item moved to location #{location_code}")}

      {:error, _changeset} ->
        {:noreply, notify_flash(socket, :error, "Failed to move item")}
    end
  end

  @spec do_restore(Socket.t(), ItemType.t(), Location.t(), integer(), String.t()) ::
          {:noreply, Socket.t()}
  defp do_restore(socket, item, location, quantity, location_code) do
    case Inventory.restore_item_type(item, %{location_id: location.id, quantity: quantity}) do
      {:ok, _updated_item} ->
        {:noreply,
         socket
         |> refresh_item_data()
         |> assign(:show_restore_modal, false)
         |> assign(:location_warning, nil)
         |> assign(:pending_restore_quantity, nil)
         |> notify_flash(:info, "Item restored to location #{location_code}")}

      {:error, _changeset} ->
        {:noreply, notify_flash(socket, :error, "Failed to restore item")}
    end
  end

  @spec process_pending_photo(map() | nil) :: {:ok, String.t()} | {:ok, nil} | {:error, term()}
  defp process_pending_photo(nil), do: {:ok, nil}

  defp process_pending_photo(%{binary: binary, filename: filename}) do
    Media.process_and_save_photo(binary, filename)
  end

  @spec format_file_size(integer()) :: String.t()
  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  @spec document_error_to_string(atom()) :: String.t()
  defp document_error_to_string(:too_large) do
    max_mb = div(Media.max_document_size(), 1024 * 1024)
    "File too large (max #{max_mb}MB)"
  end

  defp document_error_to_string(:too_many_files), do: "Only one file at a time"
  defp document_error_to_string(:not_accepted), do: "Invalid file type (use PDF, PNG, or JPEG)"
  defp document_error_to_string(err), do: "Upload error: #{inspect(err)}"

  @spec format_document_url_error(atom() | tuple()) :: String.t()
  defp format_document_url_error(:invalid_url), do: "Invalid URL format"
  defp format_document_url_error(:insecure_url), do: "URL must use HTTPS"
  defp format_document_url_error(:forbidden_host), do: "Cannot fetch from internal or private addresses"
  defp format_document_url_error(:not_a_document), do: "URL does not point to a supported document (PDF, PNG, JPEG)"
  defp format_document_url_error(:content_type_mismatch), do: "File content type changed during download"

  defp format_document_url_error(:file_too_large) do
    max_mb = div(Media.max_document_size(), 1024 * 1024)
    "Document too large (max #{max_mb}MB)"
  end

  defp format_document_url_error({:http_error, 404}), do: "Document not found (404)"
  defp format_document_url_error({:http_error, status}), do: "Failed to fetch document (HTTP #{status})"
  defp format_document_url_error({:fetch_failed, _}), do: "Network error - could not reach URL"
  defp format_document_url_error(_), do: "Failed to fetch document"

  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  defp format_changeset_errors(changeset) do
    errors =
      Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)

    "Failed to save document: #{errors}"
  end

  @spec safe_document_path(InventoryLocator.Inventory.Document.t()) :: String.t()
  defp safe_document_path(document) do
    safe_path = Path.basename(document.storage_path)
    "/documents/#{safe_path}"
  end

  # LiveComponents can't use put_flash directly - flash must be set on the parent LiveView.
  # This helper sends a message to the parent (which runs in the same process).
  @spec notify_flash(Socket.t(), atom(), String.t()) :: Socket.t()
  defp notify_flash(socket, kind, message) do
    send(self(), {:flash, kind, message})
    socket
  end
end
