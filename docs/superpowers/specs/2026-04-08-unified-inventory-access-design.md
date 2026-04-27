# Unified Inventory Access

## Problem

The current system has two completely separate paths for viewing an inventory: authenticated users get the full navbar and routes at `/`, while anonymous guests get a stripped-down experience at `/view/:code` with no navigation. Adding new pages requires duplicating routes and maintaining parallel UI paths. This doesn't scale as we add sharing features.

## Goal

Let potential users experience the real product by viewing a shared inventory. The system should feel the same regardless of how you got access — only the available actions change based on your role.

## Access Model

Three tiers, determined per-inventory:

| Tier | How you get it | `inventory_role` | `current_user` |
|---|---|---|---|
| Owner | Created the inventory | `:owner` | user struct |
| Member | Invited via share code, logged in | `:member` | user struct |
| Guest | Entered via public link, no account | `:guest` | `nil` |

Permission checks:
- **Can edit?** `role == :owner`
- **Can interact (request items)?** `role in [:owner, :member]`
- **Can view?** `role in [:owner, :member, :guest]`

## Entry Flow

### Authenticated users (Owner / Member)
1. Log in via OAuth
2. `RequireAuthenticated` plug (or equivalent) sets `current_user`
3. `InventoryHook` loads accessible inventories, determines `inventory_role`
4. Members see shared inventories in the inventory switcher dropdown (labeled "shared")

### Anonymous guests
1. Visit `/view/:code` (shared link) or enter code on landing page
2. Controller validates code, stores `guest_inventory_id` in session
3. Redirect to `/`
4. `InventoryHook` sees no `current_user` but finds `guest_inventory_id` in session
5. Loads inventory, sets `inventory_role: :guest`

The landing page gets a "Have a view-only code?" input for guests who arrive at the homepage directly.

## Navbar

Renders for everyone with an active inventory (`assigns[:current_inventory]` instead of `assigns[:current_user]`).

| Link | Owner | Member | Guest |
|---|---|---|---|
| Search | yes | yes | yes |
| Browse | yes | yes | yes |
| Locations | yes | yes | yes |
| Projects | yes | yes | yes |
| Requests | yes | yes | no |
| Inventories | yes | yes | no |
| Admin controls | if admin | no | no |
| Inventory switcher | yes | yes | no |
| User name/avatar + logout | yes | yes | no |
| Sign in | no | no | yes |

Guests see a subtle banner indicating read-only mode.

## Permission Guards

### Templates
- Edit buttons, PhotoCapture, etc.: `@inventory_role == :owner`
- Marketplace request forms: `@inventory_role in [:owner, :member]`
- "Sign in to interact" message: `@inventory_role == :guest`

### Event handlers
- Mutation events (edit, archive, delete, etc.): blocked for non-owners (unchanged)
- Marketplace request events: blocked for `:guest`, allowed for `:member` and `:owner`
- New `require_authenticated` helper in `auth_helpers.ex` for member-or-above checks

### Pages that need no permission changes
- `LocationLive.Index`, `ProjectLive.Index` — read-only for non-owners already works
- Search, browse, item display — all read paths work for any role

## Data Model

No new tables. Existing structures handle everything:

- **`inventory_members`** — tracks user-inventory membership. Any record grants `:member` access.
- **`inventory_share_codes`** — `reusable: false` creates membership on redemption; `reusable: true` establishes guest sessions.
- **Session** — `guest_inventory_id` key for anonymous guests. Ephemeral; guest re-enters via `/view/:code` if session expires.

### Member management
Owner can view all members of an inventory and revoke access (deletes the `inventory_members` record).

## File Changes

### Modify
- **`router.ex`** — `/view/:code` becomes controller redirect. Remove guest `live_session`. Main `live_session` remains under `:browser` pipeline; guests pass through because `RequireAuthenticated` skips when guest session exists.
- **`inventory_hook.ex`** — Add guest branch: no `current_user` + `guest_inventory_id` in session → load inventory, set `inventory_role: :guest`.
- **`require_authenticated.ex`** — Skip redirect when `guest_inventory_id` exists in session (guest is allowed through to main routes).
- **`root.html.heex`** — Navbar renders when `current_inventory` exists. Role-based `:if` guards on links. "Sign in" for guests.
- **`show_modal.html.heex`** — Marketplace forms gated on `role in [:owner, :member]`. "Sign in to interact" for guests. PhotoCapture hidden for non-owners (already done).
- **`auth_helpers.ex`** — Add `require_authenticated` helper.
- **`inventory.ex`** — Add `remove_member/2`.
- **`landing` page** — Add code input for guest entry.
- **Inventories page** — Add members list with revoke buttons.

### Delete
- **`guest_inventory_hook.ex`** — Replaced by guest branch in `InventoryHook`.
- **`guest.html.heex`** — Guests use `app.html.heex`.
