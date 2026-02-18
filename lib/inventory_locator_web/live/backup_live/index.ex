defmodule InventoryLocatorWeb.BackupLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.AuthHelpers

  alias InventoryLocator.Backup
  alias InventoryLocator.Backup.MaintenanceMode
  alias InventoryLocator.Backup.Settings
  alias Phoenix.LiveView.Socket

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    _ =
      if connected?(socket) do
        MaintenanceMode.subscribe()
      end

    socket =
      socket
      |> assign(:page_title, "Backups")
      |> assign(:active_tab, :daily)
      |> assign(:configured, Backup.configured?())
      |> assign(:maintenance_state, MaintenanceMode.get_state())
      |> assign(:restore_modal_open, false)
      |> assign(:restore_target, nil)
      |> assign(:restore_confirmation, "")
      |> assign(:delete_modal_open, false)
      |> assign(:delete_target, nil)
      |> assign(:backup_running, false)
      |> load_backups()
      |> load_settings()

    {:ok, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("run_backup", %{"type" => type}, socket) do
    require_admin(socket, fn socket ->
      socket = assign(socket, :backup_running, true)
      send(self(), {:run_backup, String.to_existing_atom(type)})
      {:noreply, socket}
    end)
  end

  def handle_event("open_restore_modal", %{"key" => key}, socket) do
    socket =
      socket
      |> assign(:restore_modal_open, true)
      |> assign(:restore_target, key)
      |> assign(:restore_confirmation, "")

    {:noreply, socket}
  end

  def handle_event("close_restore_modal", _params, socket) do
    socket =
      socket
      |> assign(:restore_modal_open, false)
      |> assign(:restore_target, nil)
      |> assign(:restore_confirmation, "")

    {:noreply, socket}
  end

  def handle_event("update_restore_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :restore_confirmation, value)}
  end

  def handle_event("confirm_restore", _params, socket) do
    require_admin(socket, fn socket ->
      expected = expected_confirmation(socket.assigns.restore_target)

      if socket.assigns.restore_confirmation == expected do
        send(self(), {:perform_restore, socket.assigns.restore_target})

        socket =
          socket
          |> assign(:restore_modal_open, false)
          |> put_flash(:info, "Starting database restore...")

        {:noreply, socket}
      else
        {:noreply, put_flash(socket, :error, "Confirmation text does not match")}
      end
    end)
  end

  def handle_event("open_delete_modal", %{"key" => key}, socket) do
    socket =
      socket
      |> assign(:delete_modal_open, true)
      |> assign(:delete_target, key)

    {:noreply, socket}
  end

  def handle_event("close_delete_modal", _params, socket) do
    socket =
      socket
      |> assign(:delete_modal_open, false)
      |> assign(:delete_target, nil)

    {:noreply, socket}
  end

  def handle_event("confirm_delete", _params, socket) do
    require_admin(socket, fn socket ->
      key = socket.assigns.delete_target

      case Backup.delete_backup(key) do
        :ok ->
          socket =
            socket
            |> assign(:delete_modal_open, false)
            |> assign(:delete_target, nil)
            |> load_backups()
            |> put_flash(:info, "Backup deleted")

          {:noreply, socket}

        {:error, reason} ->
          Logger.error("Backup deletion failed: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to delete backup")}
      end
    end)
  end

  def handle_event("save_settings", %{"settings" => settings_params}, socket) do
    require_admin(socket, fn socket ->
      case Backup.update_settings(settings_params) do
        {:ok, settings} ->
          socket =
            socket
            |> assign(:settings, settings)
            |> assign(:settings_changeset, Backup.change_settings(settings))
            |> put_flash(:info, "Settings saved successfully")

          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, :settings_changeset, changeset)}
      end
    end)
  end

  def handle_event("validate_settings", %{"settings" => settings_params}, socket) do
    changeset =
      socket.assigns.settings
      |> Backup.change_settings(settings_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :settings_changeset, changeset)}
  end

  @impl true
  def handle_info({:run_backup, type}, socket) do
    result =
      case type do
        :daily -> Backup.run_daily_backup()
        :weekly -> Backup.run_weekly_backup()
      end

    socket =
      socket
      |> assign(:backup_running, false)
      |> load_backups()

    socket =
      case result do
        {:ok, key} ->
          put_flash(socket, :info, "Backup completed: #{Path.basename(key)}")

        {:error, reason} ->
          Logger.error("Backup failed: #{inspect(reason)}")
          put_flash(socket, :error, "Backup failed. Check server logs for details.")
      end

    {:noreply, socket}
  end

  def handle_info({:perform_restore, key}, socket) do
    case Backup.restore_backup(key) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Database restored successfully")}

      {:error, reason} ->
        Logger.error("Restore failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Restore failed. Check server logs for details.")}
    end
  end

  def handle_info({:maintenance_state, state}, socket) do
    {:noreply, assign(socket, :maintenance_state, state)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Components

  attr :backups, :list, required: true
  attr :type, :string, required: true
  attr :configured, :boolean, required: true

  defp backup_list(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <%= if not @configured do %>
          <p class="text-base-content/60">Backups not configured.</p>
        <% else %>
          <%= if @backups == [] do %>
            <p class="text-base-content/60">No {@type} backups found.</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Size</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for backup <- @backups do %>
                    <tr>
                      <td class="font-mono">{Backup.extract_timestamp_from_key(backup.key)}</td>
                      <td>{Backup.format_size(backup.size)}</td>
                      <td class="flex gap-2">
                        <button
                          class="btn btn-warning btn-sm"
                          phx-click="open_restore_modal"
                          phx-value-key={backup.key}
                        >
                          Restore
                        </button>
                        <button
                          class="btn btn-error btn-sm btn-outline"
                          phx-click="open_delete_modal"
                          phx-value-key={backup.key}
                        >
                          Delete
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :changeset, Ecto.Changeset, required: true
  attr :settings, Settings, required: true
  attr :configured, :boolean, required: true

  defp settings_form(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <.form
          for={@changeset}
          phx-change="validate_settings"
          phx-submit="save_settings"
          class="space-y-4"
        >
          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-4">
              <input
                type="checkbox"
                name="settings[enabled]"
                checked={Phoenix.HTML.Form.normalize_value("checkbox", @changeset.data.enabled)}
                class="checkbox"
                disabled={not @configured}
              />
              <span class="label-text">Backups enabled</span>
            </label>
          </div>

          <div class="divider">Daily Backups</div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Time</span>
              </label>
              <select name="settings[daily_backup_hour]" class="select select-bordered">
                <%= for hour <- 0..23 do %>
                  <option value={hour} selected={@settings.daily_backup_hour == hour}>
                    {Settings.hour_label(hour)}
                  </option>
                <% end %>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Keep last (days)</span>
              </label>
              <input
                type="number"
                name="settings[daily_retention_days]"
                value={@settings.daily_retention_days}
                min="1"
                max="30"
                class="input input-bordered"
              />
            </div>
          </div>

          <div class="divider">Weekly Backups</div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Day</span>
              </label>
              <select name="settings[weekly_backup_day]" class="select select-bordered">
                <%= for day <- 0..6 do %>
                  <option value={day} selected={@settings.weekly_backup_day == day}>
                    {Settings.day_name(day)}
                  </option>
                <% end %>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Time</span>
              </label>
              <select name="settings[weekly_backup_hour]" class="select select-bordered">
                <%= for hour <- 0..23 do %>
                  <option value={hour} selected={@settings.weekly_backup_hour == hour}>
                    {Settings.hour_label(hour)}
                  </option>
                <% end %>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Keep last (weeks)</span>
              </label>
              <input
                type="number"
                name="settings[weekly_retention_weeks]"
                value={@settings.weekly_retention_weeks}
                min="1"
                max="52"
                class="input input-bordered"
              />
            </div>
          </div>

          <div class="divider">Storage Location</div>
          <p class="text-sm text-base-content/60">
            Backups stored in:
            <code class="bg-base-300 px-2 py-1 rounded">
              {InventoryLocator.Backup.LocalStorage.base_path()}
            </code>
          </p>
          <p class="text-sm text-base-content/60 mt-2">
            Tip: Use
            <a href="https://syncthing.net" target="_blank" class="link link-primary">Syncthing</a>
            to sync this folder to another device for off-site backups.
          </p>

          <div class="form-control mt-6">
            <button type="submit" class="btn btn-primary">Save Settings</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @spec load_backups(Socket.t()) :: Socket.t()
  defp load_backups(socket) do
    if socket.assigns.configured do
      {:ok, daily_backups} = Backup.list_daily_backups()
      {:ok, weekly_backups} = Backup.list_weekly_backups()

      socket
      |> assign(:daily_backups, daily_backups)
      |> assign(:weekly_backups, weekly_backups)
    else
      socket
      |> assign(:daily_backups, [])
      |> assign(:weekly_backups, [])
    end
  end

  @spec load_settings(Socket.t()) :: Socket.t()
  defp load_settings(socket) do
    settings = Backup.get_settings()

    socket
    |> assign(:settings, settings)
    |> assign(:settings_changeset, Backup.change_settings(settings))
  end

  @spec expected_confirmation(String.t()) :: String.t()
  defp expected_confirmation(key) do
    date = key |> Backup.extract_timestamp_from_key() |> String.split(" ") |> hd()
    "RESTORE #{date}"
  end
end
