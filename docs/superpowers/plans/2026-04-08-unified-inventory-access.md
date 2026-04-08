# Unified Inventory Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the authenticated and guest access paths so all users (owner, member, guest) use the same routes, navbar, and layouts — differentiated only by `inventory_role`.

**Architecture:** The `/view/:code` route becomes a session-establishing redirect instead of a separate LiveView. The `RequireAuthenticated` plug learns to pass guests through. The `InventoryHook` gains a guest branch. The navbar renders for everyone with an active inventory, with role-based link visibility.

**Tech Stack:** Phoenix LiveView, Elixir, PostgreSQL (no new dependencies)

---

## File Structure

### Modified files
- `lib/inventory_locator_web/plugs/require_authenticated.ex` — skip redirect for guest sessions
- `lib/inventory_locator_web/hooks/auth_hook.ex` — skip redirect for guest sessions
- `lib/inventory_locator_web/hooks/inventory_hook.ex` — add guest branch, rename `:viewer` to `:member`
- `lib/inventory_locator_web/plugs/load_inventory.ex` — add guest branch, rename `:viewer` to `:member`
- `lib/inventory_locator_web/controllers/share_controller.ex` — add `enter_guest/2` action
- `lib/inventory_locator_web/router.ex` — add guest entry route, remove guest `live_session`
- `lib/inventory_locator_web/auth_helpers.ex` — add `require_member` helper
- `lib/inventory_locator_web/components/layouts/root.html.heex` — role-based navbar
- `lib/inventory_locator_web/live/landing_live/index.html.heex` — guest code input
- `lib/inventory_locator_web/live/landing_live/index.ex` — handle guest code submission
- `lib/inventory_locator_web/live/item_live/show_modal.html.heex` — marketplace guard update
- `lib/inventory_locator_web/live/item_live/show_modal.ex` — update role type specs

### Deleted files
- `lib/inventory_locator_web/hooks/guest_inventory_hook.ex`
- `lib/inventory_locator_web/components/layouts/guest.html.heex`

### Test files
- `test/inventory_locator_web/plugs/require_authenticated_test.exs` — guest passthrough
- `test/inventory_locator/inventory/unified_access_test.exs` — role resolution tests

---

## Task 1: Rename `:viewer` to `:member` for authenticated non-owners

The current code uses `:viewer` for both authenticated members and anonymous guests. We need to distinguish them. This task renames `:viewer` to `:member` everywhere it refers to an authenticated non-owner.

**Files:**
- Modify: `lib/inventory_locator_web/hooks/inventory_hook.ex:44-47`
- Modify: `lib/inventory_locator_web/plugs/load_inventory.ex:70-72`
- Modify: `lib/inventory_locator_web/live/item_live/show_modal.ex:47,999-1007`
- Modify: `lib/inventory_locator_web/live/item_live/index.html.heex:39`
- Test: `test/inventory_locator/inventory/unified_access_test.exs`

- [ ] **Step 1: Write test for role resolution**

Create `test/inventory_locator/inventory/unified_access_test.exs`:

```elixir
defmodule InventoryLocator.Inventory.UnifiedAccessTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory

  setup do
    owner = create_test_user(%{name: "Owner", role: "admin"})
    member_user = create_test_user(%{name: "Member", role: "member"})
    inventory = create_test_inventory(%{user_id: owner.id})
    %{owner: owner, member_user: member_user, inventory: inventory}
  end

  describe "user_role_for_inventory/2" do
    test "returns :owner for inventory owner", %{owner: owner, inventory: inventory} do
      assert Inventory.user_role_for_inventory(owner.id, inventory.id) == :owner
    end

    test "returns :member for shared member", %{member_user: member_user, inventory: inventory, owner: owner} do
      {:ok, _code} = Inventory.create_share_code(inventory.id, owner.id)
      codes = Inventory.list_share_codes(inventory.id)
      code = hd(codes)
      {:ok, _member} = Inventory.redeem_share_code(code.code, member_user.id)
      assert Inventory.user_role_for_inventory(member_user.id, inventory.id) == :member
    end

    test "returns :none for unrelated user", %{inventory: inventory} do
      stranger = create_test_user(%{name: "Stranger", role: "member"})
      assert Inventory.user_role_for_inventory(stranger.id, inventory.id) == :none
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/inventory_locator/inventory/unified_access_test.exs -v`
Expected: The `:member` assertion fails because `user_role_for_inventory` currently returns `:viewer`.

- [ ] **Step 3: Rename `:viewer` to `:member` in inventory context**

In `lib/inventory_locator/inventory.ex`, find the `check_membership_role` function and change its return value from `:viewer` to `:member`. Also update `user_role_for_inventory` spec:

```elixir
# Change the spec from:
@spec user_role_for_inventory(integer(), integer()) :: :owner | :viewer | :none
# To:
@spec user_role_for_inventory(integer(), integer()) :: :owner | :member | :none
```

And the `check_membership_role` return:
```elixir
# Change from:
defp check_membership_role(member) when not is_nil(member), do: :viewer
# To:
defp check_membership_role(member) when not is_nil(member), do: :member
```

- [ ] **Step 4: Update InventoryHook role function**

In `lib/inventory_locator_web/hooks/inventory_hook.ex`, lines 44-47:

```elixir
# Change from:
@spec inventory_role(integer(), Inv.t() | nil) :: :owner | :viewer | :none
defp inventory_role(_user_id, nil), do: :none
defp inventory_role(user_id, %Inv{user_id: user_id}), do: :owner
defp inventory_role(_user_id, _inv), do: :viewer

# To:
@spec inventory_role(integer(), Inv.t() | nil) :: :owner | :member | :none
defp inventory_role(_user_id, nil), do: :none
defp inventory_role(user_id, %Inv{user_id: user_id}), do: :owner
defp inventory_role(_user_id, _inv), do: :member
```

- [ ] **Step 5: Update LoadInventory plug role function**

In `lib/inventory_locator_web/plugs/load_inventory.ex`, lines 70-72:

```elixir
# Change from:
@spec inventory_role(integer(), Inv.t()) :: :owner | :viewer
defp inventory_role(user_id, %Inv{user_id: user_id}), do: :owner
defp inventory_role(_user_id, _inv), do: :viewer

# To:
@spec inventory_role(integer(), Inv.t()) :: :owner | :member
defp inventory_role(user_id, %Inv{user_id: user_id}), do: :owner
defp inventory_role(_user_id, _inv), do: :member
```

- [ ] **Step 6: Update all template checks from `:viewer` to `:member`**

In `lib/inventory_locator_web/live/item_live/index.html.heex`, change:

```heex
<%!-- Change from: --%>
<%= if @inventory_role == :viewer do %>
<%!-- To: --%>
<%= if @inventory_role in [:member, :guest] do %>
```

In `lib/inventory_locator_web/live/item_live/show_modal.ex`, update the spec on line 47:

```elixir
# Change from:
@spec update_with_item(map(), Socket.t(), ItemType.t(), integer(), :owner | :viewer | :none) ::
# To:
@spec update_with_item(map(), Socket.t(), ItemType.t(), integer(), :owner | :member | :guest | :none) ::
```

And update `load_listings` and `load_user_requests` specs/clauses:

```elixir
# Change from:
@spec load_listings(integer(), :owner | :viewer | :none) :: [Listing.t()]
defp load_listings(item_type_id, :viewer), do: ...
# To:
@spec load_listings(integer(), :owner | :member | :guest | :none) :: [Listing.t()]
defp load_listings(item_type_id, role) when role in [:member, :guest], do: ...
```

```elixir
# Change from:
@spec load_user_requests(map(), integer(), :owner | :viewer | :none) :: [Marketplace.Request.t()]
defp load_user_requests(assigns, item_type_id, :viewer) do
# To:
@spec load_user_requests(map(), integer(), :owner | :member | :guest | :none) :: [Marketplace.Request.t()]
defp load_user_requests(assigns, item_type_id, role) when role in [:member, :guest] do
```

- [ ] **Step 7: Update unresolved_request_count in InventoryHook**

In `lib/inventory_locator_web/hooks/inventory_hook.ex`, update the spec and catch-all:

```elixir
# Change from:
@spec unresolved_request_count(Inv.t() | nil, :owner | :viewer | :none) :: non_neg_integer()
# To:
@spec unresolved_request_count(Inv.t() | nil, :owner | :member | :none) :: non_neg_integer()
```

- [ ] **Step 8: Run tests**

Run: `mix test`
Expected: All tests pass. The unified_access_test should pass now.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: rename inventory_role :viewer to :member for authenticated non-owners"
```

---

## Task 2: Guest session entry via `/view/:code`

Convert the `/view/:code` route from a LiveView to a controller action that validates the public link code, stores the inventory ID in the session, and redirects to `/`.

**Files:**
- Modify: `lib/inventory_locator_web/controllers/share_controller.ex`
- Modify: `lib/inventory_locator_web/router.ex`
- Delete: `lib/inventory_locator_web/hooks/guest_inventory_hook.ex`
- Delete: `lib/inventory_locator_web/components/layouts/guest.html.heex`
- Test: `test/inventory_locator_web/controllers/share_controller_test.exs`

- [ ] **Step 1: Write tests for guest entry**

Create `test/inventory_locator_web/controllers/share_controller_test.exs`:

```elixir
defmodule InventoryLocatorWeb.ShareControllerTest do
  use InventoryLocatorWeb.ConnCase

  alias InventoryLocator.Inventory

  setup do
    owner = create_test_user(%{name: "Owner", role: "admin"})
    inventory = create_test_inventory(%{user_id: owner.id})
    {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)
    %{owner: owner, inventory: inventory, link: link}
  end

  describe "GET /view/:code (enter_guest)" do
    test "valid public link sets guest session and redirects", %{conn: conn, link: link, inventory: inventory} do
      conn = get(conn, ~p"/view/#{link.code}")
      assert redirected_to(conn) == "/"
      assert get_session(conn, :guest_inventory_id) == inventory.id
    end

    test "invalid code redirects to landing with error", %{conn: conn} do
      conn = get(conn, ~p"/view/BADCODE")
      assert redirected_to(conn) == "/landing"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/inventory_locator_web/controllers/share_controller_test.exs -v`
Expected: FAIL — no route matches `GET /view/BADCODE` (currently it goes to the LiveView).

- [ ] **Step 3: Add `enter_guest` action to ShareController**

In `lib/inventory_locator_web/controllers/share_controller.ex`, add at the end before the closing `end`:

```elixir
@spec enter_guest(Plug.Conn.t(), map()) :: Plug.Conn.t()
def enter_guest(conn, %{"code" => code}) do
  case Inventory.resolve_public_code(code) do
    {:ok, inventory} ->
      conn
      |> put_session(:guest_inventory_id, inventory.id)
      |> redirect(to: "/")

    :invalid ->
      conn
      |> put_flash(:error, "Invalid or expired view link.")
      |> redirect(to: "/landing")
  end
end
```

- [ ] **Step 4: Update router**

In `lib/inventory_locator_web/router.ex`, replace the guest scope (lines 69-77):

```elixir
# Delete this entire block:
scope "/view", InventoryLocatorWeb do
  pipe_through [:browser_public, :rate_limit_guest]

  live_session :guest,
    on_mount: [{InventoryLocatorWeb.Hooks.GuestInventoryHook, :default}],
    layout: {InventoryLocatorWeb.Layouts, :guest} do
    live "/:code", ItemLive.Index
  end
end

# Replace with:
scope "/view", InventoryLocatorWeb do
  pipe_through [:browser_public, :rate_limit_guest]

  get "/:code", ShareController, :enter_guest
end
```

- [ ] **Step 5: Delete guest-specific files**

Delete `lib/inventory_locator_web/hooks/guest_inventory_hook.ex`.
Delete `lib/inventory_locator_web/components/layouts/guest.html.heex`.

- [ ] **Step 6: Run tests**

Run: `mix test test/inventory_locator_web/controllers/share_controller_test.exs -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: convert /view/:code from LiveView to session-establishing redirect"
```

---

## Task 3: Allow guests through RequireAuthenticated plug and AuthHook

Currently, `RequireAuthenticated` and `AuthHook` redirect unauthenticated users to `/landing`. Guests (who have `guest_inventory_id` in session but no `user_id`) need to pass through.

**Files:**
- Modify: `lib/inventory_locator_web/plugs/require_authenticated.ex`
- Modify: `lib/inventory_locator_web/hooks/auth_hook.ex`
- Test: `test/inventory_locator_web/plugs/require_authenticated_test.exs`

- [ ] **Step 1: Write tests for guest passthrough**

Create `test/inventory_locator_web/plugs/require_authenticated_test.exs`:

```elixir
defmodule InventoryLocatorWeb.Plugs.RequireAuthenticatedTest do
  use InventoryLocatorWeb.ConnCase

  alias InventoryLocatorWeb.Plugs.RequireAuthenticated

  describe "call/2" do
    test "allows authenticated users through", %{conn: conn} do
      user = create_test_user(%{name: "Auth User", role: "admin"})

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> RequireAuthenticated.call([])

      assert conn.assigns.current_user.id == user.id
      refute conn.halted
    end

    test "allows guests with guest_inventory_id through", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{guest_inventory_id: 1})
        |> RequireAuthenticated.call([])

      assert conn.assigns[:guest_session] == true
      refute conn.halted
    end

    test "redirects unauthenticated users without guest session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> RequireAuthenticated.call([])

      assert conn.halted
      assert redirected_to(conn) == "/landing"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/inventory_locator_web/plugs/require_authenticated_test.exs -v`
Expected: Guest test fails because plug redirects guests to `/landing`.

- [ ] **Step 3: Update RequireAuthenticated plug**

Replace `lib/inventory_locator_web/plugs/require_authenticated.ex`:

```elixir
defmodule InventoryLocatorWeb.Plugs.RequireAuthenticated do
  @moduledoc false
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  import Plug.Conn

  alias InventoryLocator.Auth

  require Logger

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    session = %{"user_id" => get_session(conn, :user_id)}

    case Auth.resolve_user(session) do
      {:ok, user} ->
        conn
        |> assign(:current_user, user)
        |> assign(:admin_user?, user.role == "admin")

      :stale_session ->
        Logger.warning("Session user_id #{session["user_id"]} not found in database")

        conn
        |> configure_session(drop: true)
        |> put_flash(:error, "Session expired. Please sign in again.")
        |> redirect(to: "/landing")
        |> halt()

      :unauthenticated ->
        if get_session(conn, :guest_inventory_id) do
          conn
          |> assign(:current_user, nil)
          |> assign(:admin_user?, false)
          |> assign(:guest_session, true)
        else
          conn
          |> put_flash(:error, "Please sign in to continue.")
          |> redirect(to: "/landing")
          |> halt()
        end
    end
  end
end
```

- [ ] **Step 4: Update AuthHook**

Replace `lib/inventory_locator_web/hooks/auth_hook.ex`:

```elixir
defmodule InventoryLocatorWeb.Hooks.AuthHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias InventoryLocator.Auth
  alias Phoenix.LiveView.Socket

  @spec on_mount(atom(), map(), map(), Socket.t()) :: {:cont, Socket.t()} | {:halt, Socket.t()}
  def on_mount(:default, _params, session, socket) do
    case Auth.resolve_user(session) do
      {:ok, user} ->
        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:admin_user?, user.role == "admin")}

      result when result in [:unauthenticated, :stale_session] ->
        if session["guest_inventory_id"] do
          {:cont,
           socket
           |> assign(:current_user, nil)
           |> assign(:admin_user?, false)
           |> assign(:guest_session, true)}
        else
          {:halt, redirect(socket, to: "/landing")}
        end
    end
  end
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/inventory_locator_web/plugs/require_authenticated_test.exs -v`
Expected: All 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: allow guest sessions through auth plug and hook"
```

---

## Task 4: Add guest branch to InventoryHook and LoadInventory

When a guest (no `current_user`, but `guest_inventory_id` in session) hits the InventoryHook, load that inventory and set `inventory_role: :guest`.

**Files:**
- Modify: `lib/inventory_locator_web/hooks/inventory_hook.ex`
- Modify: `lib/inventory_locator_web/plugs/load_inventory.ex`

- [ ] **Step 1: Update InventoryHook**

In `lib/inventory_locator_web/hooks/inventory_hook.ex`, add a new `on_mount` clause ABOVE the existing one (pattern matching on `current_user: nil` + guest session):

```elixir
def on_mount(:default, _params, %{"guest_inventory_id" => guest_inventory_id}, socket)
    when socket.assigns.current_user == nil do
  case Inventory.get_inventory(guest_inventory_id) do
    nil ->
      {:halt, redirect(socket, to: "/landing")}

    inventory ->
      socket =
        socket
        |> assign(:current_inventory, inventory)
        |> assign(:inventories, [inventory])
        |> assign(:admin_mode, false)
        |> assign(:inventory_role, :guest)
        |> assign(:guest_mode, true)
        |> assign(:unresolved_request_count, 0)

      {:cont, socket}
  end
end
```

Also add `import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]` (add `redirect: 2` to the existing import).

Update the spec:

```elixir
@spec on_mount(atom(), map(), map(), Socket.t()) :: {:cont, Socket.t()} | {:halt, Socket.t()}
```

In the existing `on_mount` clause, update `guest_mode` assignment:

```elixir
# Already has:
|> assign(:guest_mode, false)
# This stays as-is — the existing clause only runs for authenticated users
```

- [ ] **Step 2: Update LoadInventory plug**

In `lib/inventory_locator_web/plugs/load_inventory.ex`, add guest handling at the top of the `call` function:

```elixir
@spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
def call(conn, _opts) do
  if conn.assigns[:guest_session] do
    load_guest_inventory(conn)
  else
    load_authenticated_inventory(conn)
  end
end

@spec load_guest_inventory(Plug.Conn.t()) :: Plug.Conn.t()
defp load_guest_inventory(conn) do
  guest_inventory_id = get_session(conn, :guest_inventory_id)

  case Inventory.get_inventory(guest_inventory_id) do
    nil ->
      conn
      |> put_flash(:error, "Inventory not found.")
      |> redirect(to: "/landing")
      |> halt()

    inventory ->
      conn
      |> assign(:current_inventory, inventory)
      |> assign(:inventories, [inventory])
      |> assign(:admin_mode, false)
      |> assign(:inventory_role, :guest)
      |> assign(:guest_mode, true)
      |> assign(:unresolved_request_count, 0)
  end
end

@spec load_authenticated_inventory(Plug.Conn.t()) :: Plug.Conn.t()
defp load_authenticated_inventory(conn) do
  # ... move existing call/2 body here (the user_id, inventories, etc. logic)
end
```

- [ ] **Step 3: Run tests**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add guest branch to InventoryHook and LoadInventory plug"
```

---

## Task 5: Update navbar for role-based visibility

Change the navbar in `root.html.heex` to render for anyone with an active inventory, with role-based visibility on individual links.

**Files:**
- Modify: `lib/inventory_locator_web/components/layouts/root.html.heex`

- [ ] **Step 1: Update navbar condition and add role-based guards**

In `lib/inventory_locator_web/components/layouts/root.html.heex`, replace the navbar section (lines 34-152).

Change the outer condition from:

```heex
<%= if assigns[:current_user] do %>
```

To:

```heex
<%= if assigns[:current_inventory] do %>
```

Add `:if` guards to links that shouldn't appear for guests:

```heex
<%!-- Requests: only for authenticated users --%>
<.link :if={assigns[:current_user]} navigate={~p"/requests"} class="btn btn-ghost btn-sm md:btn-md">
  Requests
  <%= if assigns[:unresolved_request_count] && assigns[:unresolved_request_count] > 0 do %>
    <span class="badge badge-sm badge-primary">{@unresolved_request_count}</span>
  <% end %>
</.link>

<%!-- Inventories: only for authenticated users --%>
<.link :if={assigns[:current_user]} navigate={~p"/inventories"} class="btn btn-ghost btn-sm md:btn-md">
  Inventories
</.link>
```

The admin controls block already checks `assigns[:admin_mode]` which will be `false` for guests — no change needed.

Replace the user info / inventory switcher / logout section (lines 67-150) with role-aware version:

```heex
<div class="flex-none flex items-center gap-2">
  <%= if assigns[:current_user] do %>
    <%!-- Authenticated user: avatar, name, inventory switcher, admin toggle, logout --%>
    <div class="flex items-center gap-2">
      <%= if @current_user.avatar_url do %>
        <img src={@current_user.avatar_url} class="w-7 h-7 rounded-full object-cover" alt="" />
      <% end %>
      <span class="text-sm hidden md:inline">{@current_user.name}</span>
    </div>

    <%= if assigns[:inventories] != [] and assigns[:current_inventory] do %>
      <form action={~p"/switch_inventory"} method="post">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <select name="inventory_id" class="select select-bordered select-sm" onchange="this.form.submit()">
          <%= for inv <- @inventories do %>
            <option value={inv.id} selected={inv.id == @current_inventory.id}>
              {inv.name}
              <%= if inv.user_id != @current_user.id do %>
                (shared)
              <% end %>
            </option>
          <% end %>
        </select>
      </form>
    <% end %>

    <%!-- Admin toggle (existing code, unchanged) --%>
    <%= if assigns[:admin_user?] do %>
      <%!-- ... existing admin toggle form ... --%>
    <% end %>

    <form action={~p"/auth/logout"} method="post">
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <button type="submit" class="btn btn-ghost btn-sm btn-square" title="Sign out">
        <%!-- ... existing logout SVG icon ... --%>
      </button>
    </form>
  <% else %>
    <%!-- Guest: show inventory name and sign-in link --%>
    <span class="text-sm text-base-content/60">
      Viewing <strong>{@current_inventory.name}</strong> (read-only)
    </span>
    <.link navigate="/landing" class="btn btn-primary btn-sm">Sign in</.link>
  <% end %>
</div>
```

Note: Keep the existing admin toggle SVG code as-is — just nest it inside the `if assigns[:current_user]` block.

- [ ] **Step 2: Run the app and verify manually**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: render navbar for all access tiers with role-based link visibility"
```

---

## Task 6: Add guest code input to landing page

Add a "Have a view-only code?" section to the landing page so guests can enter a public link code without needing the direct URL.

**Files:**
- Modify: `lib/inventory_locator_web/live/landing_live/index.ex`
- Modify: `lib/inventory_locator_web/live/landing_live/index.html.heex`

- [ ] **Step 1: Update landing page mount to not redirect guests**

In `lib/inventory_locator_web/live/landing_live/index.ex`, the current mount redirects to `/` if auth isn't required or if logged in. But the landing page is under `:browser_public` (no auth plug), so this stays the same. We just need to add a `guest_code` assign and event handler:

```elixir
defmodule InventoryLocatorWeb.LandingLive.Index do
  @moduledoc false
  use InventoryLocatorWeb, :live_view

  alias InventoryLocator.Auth
  alias InventoryLocator.Inventory
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, session, socket) do
    if not Auth.auth_required?() or session["user_id"] do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Welcome")
       |> assign(:guest_code, "")
       |> assign(:guest_error, nil)}
    end
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("update_guest_code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :guest_code, code)}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("submit_guest_code", _params, socket) do
    code = String.trim(socket.assigns.guest_code)

    case Inventory.resolve_public_code(code) do
      {:ok, _inventory} ->
        {:noreply, push_navigate(socket, to: ~p"/view/#{code}")}

      :invalid ->
        {:noreply, assign(socket, :guest_error, "Invalid or expired code.")}
    end
  end
end
```

Note: The guest code form navigates to `/view/:code` which hits the `ShareController.enter_guest` action (from Task 2), which sets the session and redirects to `/`.

- [ ] **Step 2: Add guest code input to landing template**

In `lib/inventory_locator_web/live/landing_live/index.html.heex`, add this section between the Privacy section and the Sign In section (before `<%!-- Sign in --%>`):

```heex
<%!-- Guest access --%>
<div class="rounded-box border border-base-300 p-6 mb-12">
  <h2 class="font-semibold text-lg mb-2">Have a view-only code?</h2>
  <p class="text-sm text-base-content/70 mb-4">
    Enter the code to browse an inventory without signing in.
  </p>
  <form phx-submit="submit_guest_code" class="flex gap-2">
    <input
      type="text"
      name="code"
      value={@guest_code}
      phx-change="update_guest_code"
      phx-debounce="100"
      placeholder="Enter code"
      class="input input-bordered flex-1"
    />
    <button type="submit" class="btn btn-neutral" disabled={@guest_code == ""}>
      View Inventory
    </button>
  </form>
  <%= if @guest_error do %>
    <p class="text-error text-sm mt-2">{@guest_error}</p>
  <% end %>
</div>
```

- [ ] **Step 3: Run tests**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add guest code input to landing page"
```

---

## Task 7: Add `require_member` auth helper

Add a helper for guarding actions that require at least member-level access (owner or member, not guest).

**Files:**
- Modify: `lib/inventory_locator_web/auth_helpers.ex`

- [ ] **Step 1: Add `require_member` function**

In `lib/inventory_locator_web/auth_helpers.ex`, add after the `require_owner` function:

```elixir
@spec require_member(Socket.t(), (Socket.t() -> {:noreply, Socket.t()})) :: {:noreply, Socket.t()}
def require_member(socket, func) do
  if socket.assigns[:inventory_role] in [:owner, :member] do
    func.(socket)
  else
    {:noreply, put_flash(socket, :error, "Sign in to interact with this inventory.")}
  end
end
```

- [ ] **Step 2: Run tests**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add require_member auth helper for member-or-above access"
```

---

## Task 8: Update marketplace UI for guest vs member

Update the show_modal marketplace section so guests see "Sign in to request" and members see the request form. The existing code at line 596 already checks `@current_user == nil` — update it to check `@inventory_role == :guest`.

**Files:**
- Modify: `lib/inventory_locator_web/live/item_live/show_modal.html.heex:593-624`

- [ ] **Step 1: Update marketplace guard**

In `lib/inventory_locator_web/live/item_live/show_modal.html.heex`, find the viewer marketplace section (around line 593-624). Change:

```heex
<%!-- Change from: --%>
<%= if @current_user == nil do %>
  <p class="text-sm text-base-content/60 mt-2">
    <.link navigate="/landing" class="link link-primary">Sign in</.link>
    to request this item.
  </p>
<% else %>
  <%!-- request form --%>
<% end %>

<%!-- To: --%>
<%= if @inventory_role == :guest do %>
  <p class="text-sm text-base-content/60 mt-2">
    <.link navigate="/landing" class="link link-primary">Sign in</.link>
    to request this item.
  </p>
<% else %>
  <%!-- request form (unchanged) --%>
<% end %>
```

- [ ] **Step 2: Run tests**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: show 'sign in to request' for guests in marketplace listings"
```

---

## Task 9: Clean up and verify

Final cleanup: remove stale references, run the full test suite, and verify the complete flow.

**Files:**
- Various — grep for stale references

- [ ] **Step 1: Search for stale references to removed files**

Run:
```bash
grep -r "GuestInventoryHook\|guest_inventory_hook\|:guest.*layout\|Layouts.*:guest" lib/ --include="*.ex" --include="*.heex"
```

Remove any references found.

- [ ] **Step 2: Search for stale `:viewer` role references**

Run:
```bash
grep -r "inventory_role.*:viewer\|:viewer.*inventory_role\|== :viewer" lib/ --include="*.ex" --include="*.heex"
```

Fix any remaining `:viewer` references that should be `:member` or `in [:member, :guest]`.

- [ ] **Step 3: Run full test suite**

Run: `mix test`
Expected: All tests pass with 0 failures.

- [ ] **Step 4: Run the formatter**

Run: `mix format`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: clean up stale references from unified access refactor"
```
