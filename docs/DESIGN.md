# Inventory Locator Service - Design

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client Layer                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Desktop   │  │   Mobile    │  │  Phone Camera           │  │
│  │   Browser   │  │   Browser   │  │  (Photo Capture Only)   │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                      │                │
│         └────────────────┼──────────────────────┘                │
│                          │ WebSocket (LiveView)                  │
└──────────────────────────┼───────────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────────┐
│                    Phoenix Application                           │
│                          │                                       │
│  ┌───────────────────────▼────────────────────────────────────┐  │
│  │                    LiveView UI                              │  │
│  │  • Item Management  • Search  • Location Management        │  │
│  └───────────────────────┬────────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────▼────────────────────────────────────┐  │
│  │                   Core Contexts                             │  │
│  │  • Inventory (Items, Locations)                            │  │
│  │  • Search (Text, Fuzzy)                                    │  │
│  │  • Media (Photo Storage)                                   │  │
│  └───────────────────────┬────────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────▼─────────┐  ┌────────────────────────┐ │
│  │         Ecto + PostgreSQL       │  │   AI Search Client     │ │
│  │  • Items  • Locations  • Media  │  │   (HTTP to Python)     │ │
│  └─────────────────────────────────┘  └───────────┬────────────┘ │
└───────────────────────────────────────────────────┼──────────────┘
                                                    │ HTTP/JSON
┌───────────────────────────────────────────────────┼──────────────┐
│                    AI Search Service (Python)                    │
│                                                   │              │
│  ┌────────────────────────────────────────────────▼───────────┐  │
│  │                    FastAPI Server                          │  │
│  └────────────────────────────────────────────────┬───────────┘  │
│                                                   │              │
│  ┌────────────────────────────────────────────────▼───────────┐  │
│  │              LangChain + VertexAI                          │  │
│  │  • Semantic query interpretation                           │  │
│  │  • Inventory-aware search                                  │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Web Framework** | Phoenix 1.7+ | LiveView for real-time UI, excellent WebSocket support |
| **UI** | Phoenix LiveView | No JavaScript framework needed, real-time updates built-in |
| **Database** | PostgreSQL 15+ | Relational integrity, full-text search, mature Ecto support |
| **ORM** | Ecto | Native Elixir, migrations, changesets for validation |
| **AI Service** | Python + FastAPI | Mature AI tooling ecosystem |
| **AI Framework** | LangChain | Agent abstractions, prompt management |
| **LLM Provider** | VertexAI | Google Cloud, reliable, good pricing |
| **File Storage** | Local filesystem (MVP) | Simple, migrateable to S3/GCS later |

## Data Model

### Core Entities

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│     Shelf       │       │      Bin        │       │      Cell       │
├─────────────────┤       ├─────────────────┤       ├─────────────────┤
│ id              │──┐    │ id              │──┐    │ id              │
│ code (e.g. "A") │  │    │ code (e.g. "3") │  │    │ code (e.g. "0") │
│ name (optional) │  │    │ shelf_id        │◄─┘    │ bin_id          │◄─┘
│ description     │  │    │ name (optional) │       │ name (optional) │
└─────────────────┘  │    └─────────────────┘       └────────┬────────┘
                     │                                       │
                     └───────────────────────────────────────┘
                                      │
                                      ▼
                           ┌─────────────────────┐
                           │      Location       │
                           ├─────────────────────┤
                           │ id                  │
                           │ full_code           │ ← "A3-0" (computed)
                           │ shelf_id            │
                           │ bin_id              │
                           │ cell_id             │
                           └──────────┬──────────┘
                                      │ 1:1
                                      ▼
                           ┌─────────────────────┐
                           │     ItemType        │
                           ├─────────────────────┤
                           │ id                  │
                           │ name                │
                           │ description         │
                           │ manufacturer        │ ← nullable
                           │ model               │ ← nullable
                           │ quantity            │
                           │ location_id         │ ← unique constraint
                           │ photo_path          │
                           │ inserted_at         │
                           │ updated_at          │
                           └─────────────────────┘
```

### Key Constraints

1. **One item type per location:** `item_types.location_id` has UNIQUE constraint
2. **Location uniqueness:** Combination of (shelf_id, bin_id, cell_id) is unique
3. **Full code generation:** Computed as "{shelf.code}{bin.code}-{cell.code}"
4. **Referential integrity:** Bins require a shelf, cells require a bin
5. **No orphaned items:** Items require a location; location_id is NOT NULL
6. **Deletion protection:** Cannot delete a location that has an item; cannot delete shelf/bin with children

### Why Full Hierarchy from Day One

Starting with the full Shelf → Bin → Cell model allows experimentation while data volume is low. Migrating from a flat structure to a hierarchy after 1000+ items would be costly. Early iteration is cheap; late migration is expensive.

## Key Design Decisions

### 1. Photo Sync Between Devices

**Decision:** Use Phoenix PubSub to broadcast photos between user sessions.

When phone uploads a photo, broadcast to all sessions for that user. Desktop LiveView receives broadcast and displays photo immediately.

**Why:** Native to Phoenix, no external dependencies, real-time by default.

### 2. Duplicate Detection

**Decision:** Two-phase approach

1. **Fast check:** PostgreSQL trigram similarity (pg_trgm extension) on item name
2. **AI check (optional):** User can request semantic comparison via AI service

**Why:** Trigram catches obvious duplicates instantly. AI handles semantic similarity ("USB-C charger" vs "65W power adapter") when needed.

### 3. AI Search Integration

**Decision:** Elixir calls Python service via HTTP/JSON.

- Python service runs on same machine (MVP) or separate container (production)
- Elixir uses HTTP client (Req) to call FastAPI endpoints
- Clear boundary between inventory logic (Elixir) and AI logic (Python)

**Why:** Mature AI tooling in Python, clean separation of concerns, easy to test independently.

### 4. Text Search

**Decision:** PostgreSQL full-text search with trigram fallback.

- Primary: `tsvector/tsquery` for word-based search
- Fallback: `pg_trgm` similarity for typo tolerance
- Combined ranking for result ordering

**Why:** No external search service needed, PostgreSQL handles both well.

### 5. Location Code Format

**Decision:** Short codes like "A3-0" (Shelf A, Bin 3, Cell 0).

- Human-readable but compact for labeling

**Why:** Easy to print on labels, quick to type, unambiguous.

### 6. String-Based Location Entry

**Decision:** User types location as free-form string, system parses and validates.

- Parse "a3-0" → Shelf A, Bin 3, Cell 0
- Normalize case ("a3-0" → "A3-0")
- Validate against existing hierarchy
- If location exists and empty: use it
- If location exists and occupied: alert collision
- If location doesn't exist: prompt to create missing shelf/bin/cell

**Why:** String entry is faster than dropdown navigation for high-volume data entry. At 1000+ items, this saves significant time. System handles validation so user can type quickly without worrying about case or format.

## File Structure

```
inventory_locator/
├── lib/
│   ├── inventory_locator/
│   │   ├── inventory/           # Core inventory context
│   │   ├── search/              # Search context (text + AI client)
│   │   ├── media/               # Photo handling
│   │   └── repo.ex
│   ├── inventory_locator_web/
│   │   ├── live/                # LiveView modules
│   │   └── components/
│   └── inventory_locator_web.ex
├── priv/
│   ├── repo/migrations/
│   └── static/uploads/          # Photo storage (MVP)
├── ai_search/                   # Python service (separate directory)
│   ├── main.py
│   ├── search.py
│   └── requirements.txt
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
- **Single machine** - Phoenix + PostgreSQL + Python service co-located
- **Process management** - Mix for dev, systemd or similar for production

## Future Considerations

1. **Image-based search:** Store embeddings in pgvector, query by image similarity
2. **Mobile app:** Consider LiveView Native if web responsive proves insufficient
3. **Cloud deployment:** Fly.io (Elixir), Cloud Run (Python), Cloud SQL (Postgres)
4. **File storage:** Migrate from local filesystem to GCS/S3
