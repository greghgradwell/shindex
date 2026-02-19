# Inventory Locator Service - Design

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client Layer                             │
│  ┌─────────────┐  ┌─────────────┐                               │
│  │   Desktop   │  │   Mobile    │                               │
│  │   Browser   │  │   Browser   │                               │
│  └──────┬──────┘  └──────┬──────┘                               │
│         │                │                                       │
│         └────────────────┘                                       │
│                          │ WebSocket (LiveView)                  │
└──────────────────────────┼───────────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────────┐
│                    Phoenix Application                           │
│                          │                                       │
│  ┌───────────────────────▼────────────────────────────────────┐  │
│  │                    LiveView UI                              │  │
│  │  • Item Management  • Search  • Location  • Projects       │  │
│  └───────────────────────┬────────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────▼────────────────────────────────────┐  │
│  │                   Core Contexts                             │  │
│  │  • Inventory (Items, Locations, Projects, Sharing)         │  │
│  │  • Accounts (Users, Invites)                               │  │
│  │  • Search (Text, AI)                                       │  │
│  │  • Media (Photo Storage)                                   │  │
│  └───────────────────────┬────────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────▼─────────┐                            │
│  │         Ecto + PostgreSQL       │                            │
│  │  • Items  • Locations  • Media  │                            │
│  │  • ItemInstallations (Projects) │                            │
│  │  • Users  • Inventories         │                            │
│  │  • InventoryMembers • ShareCodes│                            │
│  └─────────────────────────────────┘                            │
└──────────────────────────────────────────────────┬──────────────┘
                                                   │ HTTPS/JSON
                                                   ▼
                              ┌────────────────────────────────────┐
                              │   Google Gemini 2.5 Flash API      │
                              │   (generativelanguage.googleapis)  │
                              └────────────────────────────────────┘
```

## Technology Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Web Framework** | Phoenix 1.8+ | LiveView for real-time UI, excellent WebSocket support |
| **UI** | Phoenix LiveView | No JavaScript framework needed, real-time updates built-in |
| **Database** | PostgreSQL 14+ | Relational integrity, pg_trgm for fuzzy search, mature Ecto support |
| **ORM** | Ecto | Native Elixir, migrations, changesets for validation |
| **AI Search** | Gemini 2.5 Flash | Direct API via Req HTTP client, prompt-based semantic search |
| **File Storage** | Local filesystem (MVP) | Simple, migrateable to S3/GCS later |

## Data Model

### Core Entities

```
┌─────────────────┐
│      User       │
├─────────────────┤
│ id              │
│ name            │
│ email           │
│ avatar_url      │
│ role            │ ← admin/member
└────────┬────────┘
         │ 1:N (ownership)
         ▼
┌─────────────────┐       ┌─────────────────┐
│      Inv        │       │InventoryMember  │
├─────────────────┤       ├─────────────────┤
│ id              │◄──────│ inventory_id    │
│ name            │       │ user_id         │ ← FK to User
│ description     │       │ role            │ ← "viewer"
│ user_id         │ ← FK  └─────────────────┘
└────────┬────────┘
         │                ┌─────────────────────┐
         │                │InventoryShareCode   │
         │                ├─────────────────────┤
         │                │ code (unique)       │
         ├───────────────►│ inventory_id        │
         │                │ role                │ ← "viewer"
         │                │ expires_at          │
         │                │ used_at             │ ← nullable
         │                │ used_by_id          │ ← FK to User
         │                │ created_by_id       │ ← FK to User
         │                └─────────────────────┘
         │
         ▼
┌─────────────────┐       ┌─────────────────┐
│     Shelf       │       │      Bin        │
├─────────────────┤       ├─────────────────┤
│ id              │──┐    │ id              │──┐
│ code (e.g. "A") │  │    │ code (e.g. "3") │  │
│ name (optional) │  │    │ shelf_id        │◄─┘
│ description     │  │    │ name (optional) │
│ inventory_id    │  │    └────────┬────────┘
└─────────────────┘  │             │
                     │             │
                     └─────────────┘
                                      │
                                      ▼
                           ┌─────────────────────┐
                           │      Location       │
                           ├─────────────────────┤
                           │ id                  │
                           │ full_code           │ ← "A-3" (computed)
                           │ bin_id              │ ← 1:1 with bin
                           └──────────┬──────────┘
                                      │ N:1 (co-location allowed)
                                      ▼
                           ┌─────────────────────┐
                           │     ItemType        │
                           ├─────────────────────┤
                           │ id                  │
                           │ name                │
                           │ description         │
                           │ manufacturer        │ ← nullable
                           │ model               │ ← nullable
                           │ quantity            │ ← >= 0
                           │ location_id         │ ← nullable (co-location OK)
                           │ photo_path          │
                           │ archived            │ ← indexed
                           │ inserted_at         │
                           │ updated_at          │
                           └──────────┬──────────┘
                                      │ 1:N
                                      ▼
                           ┌─────────────────────┐
                           │  ItemInstallation   │
                           ├─────────────────────┤
                           │ id                  │
                           │ item_type_id        │ ← FK to ItemType
                           │ project_name        │ ← uppercase
                           │ quantity            │ ← > 0
                           │ inserted_at         │
                           │ updated_at          │
                           └─────────────────────┘
```

### Key Constraints

1. **Co-location allowed:** Multiple items can share a location (user warned but not blocked)
2. **Location uniqueness:** One location per bin (bin_id is unique in locations table)
3. **Full code generation:** Computed as "{shelf.code}-{bin.code}"
4. **Referential integrity:** Bins require a shelf, locations require a bin
5. **Active items require location:** `CHECK ((archived = false AND location_id IS NOT NULL) OR (archived = true AND location_id IS NULL))`
   - Active items (archived=false) MUST have a location
   - Archived items (archived=true) MUST NOT have a location (frees location for reuse)
6. **Deletion protection:** Cannot delete a location with an active item; cannot delete shelf/bin with children
7. **Quantity validation:** `CHECK (quantity >= 0)` - allows zero for archived items
8. **Item installations:** (item_type_id, project_name) unique constraint, quantity > 0
9. **Inventory ownership:** Every inventory has a user_id (NOT NULL, on_delete: :restrict). Per-user unique names via `[:user_id, :name]` index.
10. **Inventory membership:** (user_id, inventory_id) unique constraint. Role is "viewer" only.
11. **Share codes:** One-time-use, 7-day expiry. Unique code. Redemption is atomic (insert member + mark used in transaction).

### Why Two-Level Hierarchy

The Shelf → Bin model provides sufficient granularity for workshop organization without the complexity of a third level. Each bin maps to exactly one location, simplifying both the data model and the user experience. Location codes like "A-3" are intuitive and quick to type.

## Key Design Decisions

### 1. Duplicate Detection

**Decision:** Two-phase approach

1. **Fast check:** PostgreSQL trigram similarity (pg_trgm extension) on item name
2. **AI check (optional):** User can request semantic comparison via AI service

**Why:** Trigram catches obvious duplicates instantly. AI handles semantic similarity ("USB-C charger" vs "65W power adapter") when needed.

### 2. AI Search Integration

**Decision:** Direct Gemini API calls from Elixir via Req HTTP client.

- Module: `lib/inventory_locator/search/ai.ex`
- Model: Gemini 2.5 Flash
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent`
- Auth: `x-goog-api-key` header from `GEMINI_API_KEY` env var

**Flow:**
1. Build prompt with search query + item list (ID, name, manufacturer, description)
2. POST to Gemini API with low temperature (0.1) for focused results
3. Parse JSON array of matching item IDs from response
4. Fallback to regex extraction if JSON malformed

**Why:** Simpler than Python service, no deployment complexity, sufficient for MVP semantic search.

### 3. Text Search

**Decision:** PostgreSQL full-text search with trigram fallback.

- Primary: `tsvector/tsquery` for word-based search
- Fallback: `pg_trgm` similarity for typo tolerance
- Combined ranking for result ordering

**Why:** No external search service needed, PostgreSQL handles both well.

### 4. Location Code Format

**Decision:** Fixed delimiter format: `shelf-bin` (e.g., "A-3", "tall_workbench-12")

**Format Rules:**
- **Delimiter:** Fixed single dash (`-`) between components
- **Shelf codes:**
  - Letters (a-z, A-Z), underscores, and numbers (after first character)
  - Must start with a letter
  - No leading or trailing underscores
  - 1-50 characters
  - Case-insensitive (normalized to uppercase)
  - Examples: `A`, `TALL_WORKBENCH`, `shelf_a`, `ABC_123`
- **Bin codes:**
  - Integers only (1-999)
  - No leading zeros
  - Examples: `1`, `3`, `12`, `999`

**Examples:**
- `a-3` → Shelf: "A", Bin: "3"
- `tall_workbench-12` → Shelf: "TALL_WORKBENCH", Bin: "12"
- `B-999` → Shelf: "B", Bin: "999"

**Invalid Examples:**
- `tall-workbench-3` ❌ (dash in shelf name)
- `_shelf-3` ❌ (leading underscore)
- `A-03` ❌ (leading zero in bin)
- `A-1000` ❌ (bin out of range)
- `123-3` ❌ (shelf starts with number)

**Why:** Fixed delimiter enables unambiguous parsing. Integer-only bin codes ensure simple validation and prevent entry errors. Shelf name flexibility accommodates descriptive labels while maintaining parseability.

### 5. String-Based Location Entry

**Decision:** User types location as free-form string, system parses and validates.

**Parsing Flow:**
1. Split on `-` delimiter (must have exactly 2 parts)
2. Validate each component against schema rules (Shelf, Bin modules)
3. Normalize shelf code to uppercase
4. Return parsed components or validation error

**Validation Flow:**
1. Walk database hierarchy (Shelf → Bin → Location)
2. Determine which entities exist
3. Return status:
   - `:needs_creation` with list of missing entities
   - `:exists_empty` if location exists with no item
   - `:exists_occupied` if location has an item

**Why:** String entry is faster than dropdown navigation for high-volume data entry. At 1000+ items, this saves significant time. Validation logic lives in schema modules (single source of truth), and parser delegates to them for flexibility.

### 6. Item Installations (Projects)

**Decision:** Track items installed in project builds.

**Schema:**
- `item_installations` table
- Fields: item_type_id (FK), project_name (uppercase), quantity (> 0)
- Unique constraint on (item_type_id, project_name)

**Workflow:**
1. "Install" X units of item into named project
2. Reduces available quantity shown in inventory
3. "Dismantle" returns all items to stock
4. Cannot dismantle if project contains archived items

**Why:** Know where every item is, even when installed in a project rather than storage.

### 7. Photo Capture with URL Fetching

**Decision:** Consolidated PhotoCapture LiveComponent with secure URL fetching.

**Architecture:**
- Reusable `PhotoCapture` LiveComponent used in ShowModal
- Supports file upload (via LiveView uploads) and URL fetching (via Req HTTP client)
- Parent-child communication via `send(self(), message)` pattern
- AutoConfirmUpload JS hook bridges upload completion to Save/Cancel UI

**URL Fetching Security (Defense in Depth):**
1. **URL validation:** HTTPS-only, reject file://, data://, ftp://
2. **Host blocklist (SSRF protection):**
   - Localhost: `127.x.x.x`, `localhost`
   - Private networks: `10.x.x.x`, `172.16-31.x.x`, `192.168.x.x`
   - Cloud metadata: `169.254.x.x`, `metadata.google.internal`
   - IPv6 localhost: `::1`, `::`
3. **HEAD request:** Validate `Content-Type: image/*` before downloading body
4. **Size limits:** 10MB download max, 5MB preview max (prevents browser crashes from large data URIs)
5. **Timeout:** 5 second receive timeout

**Why:** Users often have product images in browser tabs. URL fetching is faster than download → re-upload. Security layers prevent SSRF attacks that could access internal services or cloud metadata endpoints.

## File Structure

```
inventory_locator/
├── lib/
│   ├── inventory_locator/
│   │   ├── accounts/            # User management context
│   │   │   ├── user.ex
│   │   │   ├── user_identity.ex
│   │   │   └── invite_code.ex
│   │   ├── inventory/           # Core inventory context
│   │   │   ├── inv.ex           # Inventory schema (belongs_to user)
│   │   │   ├── item_type.ex
│   │   │   ├── item_installation.ex
│   │   │   ├── inventory_member.ex    # Sharing membership
│   │   │   ├── inventory_share_code.ex # One-time share codes
│   │   │   ├── location.ex
│   │   │   ├── shelf.ex, bin.ex
│   │   │   └── location_parser.ex
│   │   ├── search/
│   │   │   └── ai.ex            # Gemini API integration
│   │   ├── media.ex             # Photo handling
│   │   └── repo.ex
│   ├── inventory_locator_web/
│   │   ├── plugs/
│   │   │   ├── require_authenticated.ex
│   │   │   └── load_inventory.ex    # User-scoped inventory loading
│   │   ├── hooks/
│   │   │   ├── auth_hook.ex
│   │   │   └── inventory_hook.ex    # User-scoped, assigns inventory_role
│   │   ├── controllers/
│   │   │   ├── auth_controller.ex   # OAuth + registration
│   │   │   ├── share_controller.ex  # Share code redemption
│   │   │   └── inventory_controller.ex
│   │   ├── live/
│   │   │   ├── item_live/       # Search, detail modal
│   │   │   ├── location_live/   # Hierarchy view
│   │   │   ├── project_live/    # Project management
│   │   │   └── inventory_live/  # Inventory CRUD + sharing UI
│   │   ├── auth_helpers.ex      # require_admin, require_owner
│   │   └── components/
│   │       ├── ghost_autocomplete.ex
│   │       └── photo_capture.ex
│   └── inventory_locator_web.ex
├── assets/
│   └── js/
│       └── hooks/               # JavaScript hooks
│           ├── ghost_autocomplete.js
│           ├── focus_first_empty.js
│           └── auto_confirm_upload.js
├── priv/
│   ├── repo/migrations/
│   └── static/uploads/          # Photo storage (MVP)
├── config/
├── test/
└── mix.exs
```

### 8. Authentication

**Decision:** OAuth-only via LinkedIn and GitHub. No email/password.

**Why:** Real identities build community trust. OAuth eliminates password storage and the associated security burden. LinkedIn + GitHub cover the target audience (professionals and technical users).

**Library:** [Ueberauth](https://github.com/ueberauth/ueberauth) with `ueberauth_github` and `ueberauth_linkedin` strategies.

**Flow:**
1. User visits landing page, clicks "Sign in with LinkedIn" or "Sign in with GitHub"
2. OAuth redirect → provider → callback with profile info (name, email, avatar)
3. First-time users must enter an invite code to complete registration
4. Returning users are signed in directly (matched by provider + provider UID)

**Schema:**
- `users` table: id, name, email, avatar_url, role (admin/member), inserted_at
- `user_identities` table: user_id, provider (github/linkedin), provider_uid, provider_email
- `invite_codes` table: code, created_by, used_by, expires_at, used_at

**Authorization model (three layers):**
- **Admin (site-level):** Generate invite codes, manage backups. First user is auto-admin. Checked via `require_admin`.
- **Owner (per-inventory):** Create/edit/delete inventories, manage items/locations/projects, generate share codes, remove members. Checked via `require_owner` (for current inventory) or `require_inventory_owner` (for a specific inventory).
- **Viewer (per-inventory):** Read-only access to shared inventories. Cannot modify items, locations, or projects.

### 9. Inventory Sharing

**Decision:** One-time-use share codes with 7-day expiry. Viewers get read-only access.

**Flow:**
1. Owner generates a share code from the Inventories page
2. Owner sends the share URL to another user
3. Recipient visits the URL, sees a confirmation page (inventory name, shared by, access level)
4. Recipient clicks "Accept Invite" to redeem the code
5. Recipient gains viewer access to the inventory (appears in their dropdown with "(shared)" suffix)
6. Owner can remove members from the share modal

**Schema:**
- `inventory_members` table: user_id, inventory_id, role ("viewer"), unique on (user_id, inventory_id)
- `inventory_share_codes` table: code (unique), inventory_id, role, expires_at, used_at, used_by_id, created_by_id

**Access queries:** `list_accessible_inventories/1` uses `LEFT JOIN` on `inventory_members` to include both owned and shared inventories.

**Why one-time-use codes over persistent invite links:** Limits exposure if a link is shared beyond the intended recipient. Matches the existing invite code pattern.

### 9. Request Workflow

**Decision:** Simple status-based workflow using Ecto.Enum. No state machine library.

**Schema:**
- `listings` table: item_type_id, type (borrow/lease/sale), price (nullable), notes, active
- `requests` table: listing_id, requester_id (user), status (pending/approved/denied/completed), message, admin_notes

**Status transitions:** pending → approved/denied, approved → completed

**Notifications:** Swoosh for email (async via Oban). Phoenix PubSub for real-time in-app notifications.

## Security Considerations

| Concern | Mitigation |
|---------|------------|
| Photo uploads | Validate file type, limit size, sanitize filenames |
| SQL injection | Ecto parameterized queries (default) |
| XSS | Phoenix HTML escaping (default) |
| CSRF | Phoenix CSRF tokens (default) |
| Authentication | OAuth only (LinkedIn, GitHub) via Ueberauth |
| Registration | Invite-only (codes with expiration) |
| Infrastructure | Dedicated VM, unprivileged app user, firewall |
| Reverse proxy | Caddy with TLS, only 80/443 exposed |
| Database | Dedicated PostgreSQL user, inventory DB only |

## Deployment

### Development (Current)
- **Raspberry Pi** - Local development with `mix phx.server`
- **PostgreSQL** co-located on same device

### Production (Phase 9)
- **Dedicated GCP Compute Engine VM** - Isolated from other workloads
- **Caddy** reverse proxy with automatic TLS (Let's Encrypt)
- **Phoenix release** managed by systemd
- **PostgreSQL** co-located on VM
- **Custom domain** pointing to VM IP
- **Firewall** - SSH (key-auth only) + HTTP/HTTPS only
- **Unprivileged user** - Phoenix runs as dedicated `inventory` user

## Future Considerations

1. **Image-based search:** Store embeddings in pgvector, query by image similarity
2. **Mobile app:** Consider LiveView Native if web responsive proves insufficient
3. **Cloud Run migration:** When 24/7 availability needed, containerize and migrate (requires GCS for photos, Cloud SQL for DB)
4. **Open registration:** Remove invite-code requirement when community is established
5. **Additional sharing roles:** Editor role for collaborative inventory management
6. **Cross-inventory discovery:** Browse and search across inventories from different owners
