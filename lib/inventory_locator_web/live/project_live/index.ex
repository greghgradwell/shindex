defmodule InventoryLocatorWeb.ProjectLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    projects = Inventory.list_all_projects_with_items()

    {:ok,
     socket
     |> assign(:projects, projects)
     |> assign(:page_title, "Projects")
     |> assign(:show_archived_modal, false)
     |> assign(:archived_items, [])
     |> assign(:blocked_project, nil)
     |> assign(:selected_item_id, nil)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("dismantle_project", %{"project" => project_name}, socket) do
    case Inventory.uninstall_all_from_project(project_name) do
      {:ok, count} ->
        projects = Inventory.list_all_projects_with_items()

        message =
          if count > 0,
            do: "Dismantled #{project_name}: #{count} items returned to stock",
            else: "Dismantled #{project_name}"

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> put_flash(:info, message)}

      {:error, :has_archived_items} ->
        archived_items = Inventory.list_archived_items_in_project(project_name)

        {:noreply,
         socket
         |> assign(:show_archived_modal, true)
         |> assign(:archived_items, archived_items)
         |> assign(:blocked_project, project_name)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to dismantle project")}
    end
  end

  def handle_event("close_archived_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_archived_modal, false)
     |> assign(:archived_items, [])
     |> assign(:blocked_project, nil)}
  end

  def handle_event("open_item_modal", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_item_id, String.to_integer(id))}
  end

  @impl true
  @spec handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:close_item_modal}, socket) do
    projects = Inventory.list_all_projects_with_items()

    {:noreply,
     socket
     |> assign(:selected_item_id, nil)
     |> assign(:projects, projects)}
  end

  def handle_info({:item_deleted, item_name}, socket) do
    projects = Inventory.list_all_projects_with_items()

    {:noreply,
     socket
     |> assign(:selected_item_id, nil)
     |> assign(:projects, projects)
     |> put_flash(:info, "Deleted: #{item_name}")}
  end
end
