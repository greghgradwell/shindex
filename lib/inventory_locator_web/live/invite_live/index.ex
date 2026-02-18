defmodule InventoryLocatorWeb.InviteLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  import InventoryLocatorWeb.AuthHelpers

  alias InventoryLocator.Accounts
  alias Phoenix.LiveView.Socket

  require Logger

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    if socket.assigns.admin_user? do
      codes = Accounts.list_invite_codes()

      {:ok,
       socket
       |> assign(:page_title, "Invite Codes")
       |> assign(:invite_codes, codes)}
    else
      {:ok,
       socket
       |> assign(:invite_codes, [])
       |> put_flash(:error, "Admin access required.")
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("generate", _params, socket) do
    require_admin(socket, fn socket ->
      case Accounts.create_invite_code(socket.assigns.current_user.id) do
        {:ok, _invite} ->
          {:noreply,
           socket
           |> assign(:invite_codes, Accounts.list_invite_codes())
           |> put_flash(:info, "Invite code generated.")}

        {:error, reason} ->
          Logger.warning("Failed to create invite code: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to generate invite code.")}
      end
    end)
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    require_admin(socket, fn socket ->
      case Accounts.revoke_invite_code(String.to_integer(id)) do
        {:ok, _invite} ->
          {:noreply,
           socket
           |> assign(:invite_codes, Accounts.list_invite_codes())
           |> put_flash(:info, "Invite code revoked.")}

        {:error, :already_used} ->
          {:noreply, put_flash(socket, :error, "Cannot revoke an already-used code.")}

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "Invite code not found.")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Invite Codes</h1>
        <button phx-click="generate" class="btn btn-primary btn-sm">Generate New Code</button>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Code</th>
              <th>Created By</th>
              <th>Expires</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for code <- @invite_codes do %>
              <tr>
                <td class="font-mono">{code.code}</td>
                <td>{if code.created_by, do: code.created_by.name, else: "System"}</td>
                <td>{Calendar.strftime(code.expires_at, "%Y-%m-%d %H:%M")}</td>
                <td>
                  <%= cond do %>
                    <% code.used_at != nil -> %>
                      <span class="badge badge-ghost">
                        Used by {code.used_by && code.used_by.name}
                      </span>
                    <% DateTime.compare(code.expires_at, DateTime.utc_now()) == :lt -> %>
                      <span class="badge badge-error">Expired</span>
                    <% true -> %>
                      <span class="badge badge-success">Active</span>
                  <% end %>
                </td>
                <td>
                  <%= if code.used_at == nil and DateTime.compare(code.expires_at, DateTime.utc_now()) == :gt do %>
                    <button
                      phx-click="revoke"
                      phx-value-id={code.id}
                      class="btn btn-error btn-xs"
                      data-confirm="Revoke this invite code?"
                    >
                      Revoke
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if @invite_codes == [] do %>
        <div class="text-center text-base-content/50 py-8">
          No invite codes yet. Generate one to invite users.
        </div>
      <% end %>
    </div>
    """
  end
end
