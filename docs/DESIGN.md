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
│  │  • Inventory (Items, Locations, Projects)                  │  │
│  │  • Search (Text, AI)                                       │  │
│  │  • Media (Photo Storage)                                   │  │
│  └───────────────────────┬────────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────▼─────────┐                            │
│  │         Ecto + PostgreSQL       │                            │
│  │  • Items  • Locations  • Media  │                            │
│  │  • ItemInstallations (Projects) │                            │
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
│   │   ├── inventory/           # Core inventory context
│   │   │   ├── item_type.ex
│   │   │   ├── item_installation.ex  # Project tracking
│   │   │   ├── location.ex
│   │   │   ├── shelf.ex, bin.ex
│   │   │   └── location_parser.ex
│   │   ├── search/
│   │   │   └── ai.ex            # Gemini API integration
│   │   ├── media.ex             # Photo handling
│   │   └── repo.ex
│   ├── inventory_locator_web/
│   │   ├── live/
│   │   │   ├── item_live/       # Search, detail modal
│   │   │   ├── location_live/   # Hierarchy view
│   │   │   └── project_live/    # Project management
│   │   └── components/
│   │       ├── ghost_autocomplete.ex
│   │       └── photo_capture.ex  # Reusable photo upload/URL fetch
│   └── inventory_locator_web.ex
├── assets/
│   └── js/
│       └── hooks/               # JavaScript hooks
│           ├── ghost_autocomplete.js
│           ├── focus_first_empty.js
│           └── auto_confirm_upload.js  # Upload completion → Save/Cancel
├── priv/
│   ├── repo/migrations/
│   └── static/uploads/          # Photo storage (MVP)
├── config/
├── test/
└── mix.exs
```

## Security Considerations (Post-MVP)

| Concern | Mitigation |
|---------|------------|
| Photo uploads | Validate file type, limit size, sanitize filenames |
| SQL injection | Ecto parameterized queries (default) |
| XSS | Phoenix HTML escaping (default) |
| CSRF | Phoenix CSRF tokens (default) |
| Auth (future) | Phoenix.Token for invite links, phx_gen_auth for users |

## Deployment (MVP)

- **Local network only** - No public internet exposure initially
- **Single machine** - Phoenix + PostgreSQL co-located
- **Process management** - Mix for dev, systemd or similar for production

## Future Considerations

1. **Image-based search:** Store embeddings in pgvector, query by image similarity
2. **Mobile app:** Consider LiveView Native if web responsive proves insufficient
3. **Cloud deployment:** Fly.io (Elixir), Cloud SQL (Postgres)
4. **File storage:** Migrate from local filesystem to GCS/S3
