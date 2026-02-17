# Inventory Locator Service - Implementation Plan

## Overview

Core MVP (Phases 1-6): add items, find items, AI-powered search. **Complete.**

Next: public deployment with authentication and a community marketplace for borrowing, leasing, and selling items.

**Target:** Publicly accessible inventory with invite-only community and item request workflow.

## Phase Status

| Phase | Status | Description |
|-------|--------|-------------|
| 1 | ✅ Complete | Foundation - schema, context, parser, tooling |
| 2 | ✅ Complete | Basic UI - locations, search, items, camera, shelves |
| 3.1 | ✅ Complete | Text search (done in Phase 2.2) |
| 3.2 | Deferred | Duplicate detection |
| 4 | ✅ Complete | AI search (Gemini API) |
| 4.5 | ✅ Complete | Projects feature |
| 4.7 | ✅ Complete | Multi-inventory support |
| 4.8 | ✅ Complete | Backup system |
| 5 | ✅ Removed | ~~Multi-device photo sync~~ (workflow changed) |
| 6 | ✅ Complete | Polish and scale |
| 7 | Ongoing | Full catalogue (1000+ items) |
| 8 | Deferred | Image-based search |
| 9 | Pending | Auth + public deployment |
| 10 | Pending | Requests + marketplace |
| 11 | Future | Multi-user inventories |

## Phase 1: Foundation

### 1.1 Project Setup
- [x] Initialize Phoenix project with LiveView
- [x] Configure PostgreSQL database
- [x] Set up development environment (asdf/mise for Elixir/Erlang)
- [x] Create initial project structure per DESIGN.md

**Versions:**
- Erlang/OTP 28.3
- Elixir 1.19.4-otp-28
- Phoenix 1.8.3
- PostgreSQL 14.20

### 1.2 Database Schema
- [x] Create Shelf migration (code, name, description)
- [x] Create Bin migration (code, name, shelf_id with foreign key)
- [x] Create Cell migration (code, name, bin_id with foreign key)
- [x] Create Location migration (shelf_id, bin_id, cell_id, full_code computed)
- [x] Create ItemType migration (name, description, quantity, photo_path, location_id)
- [x] Add unique constraint on ItemType.location_id
- [x] Add unique constraint on Location (shelf_id, bin_id, cell_id)
- [x] Enable pg_trgm extension for fuzzy search
- [x] Create trigram index on ItemType.name

### 1.3 Core Inventory Context
- [x] Implement Shelf schema and changeset
- [x] Implement Bin schema and changeset (belongs_to Shelf)
- [x] Implement Cell schema and changeset (belongs_to Bin)
- [x] Implement Location schema and changeset
- [x] Implement ItemType schema and changeset
- [x] Implement Inventory context with minimal public API (7 functions, all CRUD private)
- [x] Write tests for product functionality (deleted implementation detail tests)

### 1.4 Location Code Parser
- [x] Implement location code parser ("a-3-0" → {shelf: "A", bin: "3", cell: "0"})
- [x] Handle case normalization
- [x] Validate parsed result against existing hierarchy
- [x] Return status: :exists_empty, :exists_occupied, :needs_creation
- [x] Write tests for parsing edge cases

### 1.5 Code Quality Tooling ✅ COMPLETE
- [x] Add Dialyzer for static type analysis
- [x] Add Credo for code linting and consistency
- [x] Add Styler for automatic code formatting
- [x] Configure PLT caching for faster Dialyzer runs

**Go/No-Go:** Can create locations and items via IEx console. Location parser handles "a-3-0" correctly.

## Phase 2: Basic UI

**UX Decisions:**
- Search-first interface (no default list for 1000+ items)
- Hybrid workflow: phone photo capture → desktop data entry
- Inline location creation (type "A-3-0" → "Create?" → one click)
- Archive pattern: archived items stay searchable, location is freed
  - When archiving: location_id → NULL (frees location for reuse)
  - When restoring: user must assign new location before saving

**Phase 2 Complete.**

### 2.0 Schema: Archive Support
- [x] Add `archived` boolean field to item_types (indexed)
- [x] Make `location_id` nullable with bidirectional constraint:
  - Active items (archived=false) MUST have location_id
  - Archived items (archived=true) MUST have location_id=NULL (frees location)
- [x] Allow `quantity >= 0` (change from `> 0`)
- [x] Update ItemType schema with bidirectional archive validation
- [x] Add comprehensive tests for archive/restore lifecycle
- [x] Add archive/restore functions to Inventory context (via update_item_type)

### 2.1 Location Management UI
- [x] Create LocationLive.Index - Gantt-chart hierarchical view (shelf→bin→cell)
- [x] Display occupied vs empty status for each location
- [x] Add click-to-show quickview modal (photo/name/description/quantity)
- [x] Add delete for empty locations (block if occupied, data-confirm)
- [x] Count locations by occupancy stats
- [x] Write tests for location display and deletion

### 2.2 Search Interface (Search-First) ✅ COMPLETE
- [x] Create ItemLive.Index with search box (no default list)
- [x] Implement debounced search with pg_trgm fuzzy matching (handles typos)
- [x] Add result ordering: in-stock first, then archived (ORDER BY archived ASC)
- [x] Add archived items toggle (default: hidden)
- [x] Style archived items with reduced opacity (visually distinct)
- [x] Add checkbox filters: missing manufacturer/model/description (OR logic)
- [x] Display results in photo grid
- [x] Write tests for search flow and filtering (26 new tests, 107 total passing)

### 2.3 Item Detail View (Modal) ✅ COMPLETE
- [x] Create ItemLive.Show with full item display (page version)
- [x] Add quantity increment/decrement controls
- [x] Add archive confirmation when qty→0
- [x] Add restore form for archived items (assign new location)
- [x] Add move-to-location functionality
- [x] Add install/uninstall to projects functionality
- [x] Convert from page to modal (ShowModal LiveComponent)
- [x] Remove /items/:id route (modal-only access)
- [x] Wire modal to ItemLive.Index, LocationLive.Index, and ProjectLive.Index

### 2.4 Add Item Flow (Hybrid Workflow) ✅ COMPLETE
- [x] Add image dependency for photo downsampling (~0.62)
- [x] Implement server-side photo downsampling (1920x1080, ~85% quality) - Media.ex
- [x] Create CameraLive.Index for mobile photo capture + quick entry
  - [x] Required fields: name, location (with inline creation via ensure_location_with_code)
  - [x] Optional fields: description, manufacturer, model, quantity (toggle to show)
  - [x] Save immediately after photo + required fields
  - [x] Recently saved items displayed in session
- [x] Implement photo upload + downsample (no PubSub - refresh page to see new items)
- [x] Update ItemLive.Index/ShowModal with batch completion mode
  - [x] Auto-enter edit mode when filters are active
  - [x] Auto-advance to next incomplete item on save
  - [x] Focus first empty field (FocusFirstEmpty JS hook)
  - [x] Progress indicator ("X remaining")
  - [x] Dynamic form IDs for proper state reset between items
- [x] Add location input with real-time validation (GhostAutocomplete + co-location warnings)
- [x] Add inline location creation (ensure_location_with_code creates missing hierarchy)

### 2.5 Items Table View
- [x] Add `list_all_items/1` function to Inventory context with sorting
- [x] Add view mode toggle to ItemLive.Index (Search / Browse tabs)
- [x] Implement table view with sortable columns (name, manufacturer, location)
- [x] Extract search UI into `search_view` component
- [x] Create `table_view` and `sort_indicator` components

### 2.6 Polish & UX ✅ COMPLETE
- [x] Batch completion UX (progress indicator, auto-advance, auto-focus)
- [x] Archived item opacity/styling

### 2.7 Photo Capture Consolidation ✅ COMPLETE
- [x] Create reusable PhotoCapture LiveComponent
  - [x] Supports file upload (LiveView uploads with auto_upload)
  - [x] Supports URL fetching with security protections
  - [x] Parent notification via `send(self(), {:photo_pending, id, data})`
- [x] Add URL fetching to Media module with defense-in-depth security:
  - [x] HTTPS-only validation
  - [x] SSRF protection (blocklist for private IPs, localhost, cloud metadata)
  - [x] HEAD request to validate Content-Type before download
  - [x] Size limits (10MB download, 5MB preview)
- [x] Create AutoConfirmUpload JS hook for seamless mobile UX
- [x] Refactor CameraLive to use PhotoCapture component
- [x] Refactor ShowModal to use PhotoCapture component
- [x] Add inline error display (fixed LiveComponent flash issue)
- [x] Add 22 SSRF protection tests

### 2.8 Shelf Management ✅ COMPLETE
Transform location system from auto-create to explicit management.

- [x] Add shelf CRUD: create with bins, rename with cascading updates, delete empty
- [x] Add bin/cell creation buttons with sequential numbering
- [x] Add location validation requiring existing shelf+bin before item placement
- [x] Add cell creation confirmation modal for new cells during move/restore
- [x] Add "Show cells" toggle with localStorage persistence
- [x] Sort shelves by underscore count (tier-based grouping)
- [x] Allow numbers in shelf codes (e.g., SHELF_2)
- [x] Security: Fix malformed nested HTML links, localStorage key whitelist

**Go/No-Go:** ✅ Phone workflow sub-30s, batch completion efficient, search ordering correct, photos ~300KB. (Milestone A)

## Phase 3: Search

### 3.1 Text Search ✅ COMPLETE (Implemented in Phase 2.2)
- [x] Implement full-text search in Inventory context
- [x] Add trigram similarity for typo tolerance (pg_trgm with similarity > 0.3)
- [x] Wire search box to LiveView with debounce (300ms)
- [x] Display results with relevance ordering (ORDER BY similarity DESC, archived ASC)

**Note:** Originally planned as separate phase, but implemented directly in Phase 2.2 since trigram index already existed from Phase 1.2.

### 3.2 Duplicate Detection
- [ ] On item add, query for similar items by name
- [ ] Display "Did you mean?" suggestions
- [ ] Allow user to select existing item or proceed with new
- [ ] Add "Definitely new" checkbox to skip duplicate check

**Go/No-Go:** Duplicate detection works. (Milestone B)

## Phase 4: AI Search ✅ COMPLETE

### 4.1 Gemini API Integration
- [x] Create `lib/inventory_locator/search/ai.ex`
- [x] Implement direct Gemini 2.5 Flash API calls via Req
- [x] Build prompt with item list and search query
- [x] Parse JSON response for ranked item IDs
- [x] Handle malformed responses with regex fallback
- [x] Add API key validation and error handling

### 4.2 LiveView Integration
- [x] Add AI search confirmation modal to ItemLive.Index
- [x] Implement async search with loading state
- [x] Display AI results with relevance ordering
- [x] Handle API errors gracefully

**Go/No-Go:** ✅ Semantic search works. "mipi camera" finds related items. (Milestone C)

## Phase 4.5: Projects Feature ✅ COMPLETE

### 4.5.1 Schema
- [x] Create `item_installations` migration
- [x] Add ItemInstallation schema with constraints

### 4.5.2 Context Functions
- [x] install_to_project/3, uninstall_from_project/2
- [x] list_all_projects_with_items/0
- [x] uninstall_all_from_project/1 (dismantle)

### 4.5.3 UI
- [x] ProjectLive.Index for project listing
- [x] Install/uninstall in ItemLive.ShowModal
- [x] Dismantle with archived item handling

**Go/No-Go:** ✅ Items track across projects.

## Phase 4.7: Multi-Inventory Support ✅ COMPLETE

Manage multiple inventories (e.g., workshop vs. household) with full CRUD operations.

### 4.7.1 Schema
- [x] Create Inv schema and inventories table
- [x] Add inventory_id foreign keys to shelves and item_types
- [x] Configure cascade delete for inventory removal

### 4.7.2 Context Functions
- [x] list_inventories_with_counts/0 (shelf and item counts)
- [x] create_inventory/1, update_inventory/2, delete_inventory/1
- [x] Prevent deletion of last inventory

### 4.7.3 Infrastructure
- [x] LoadInventory plug for session-based inventory selection
- [x] InventoryHook for LiveView inventory context
- [x] Resilient to stale session IDs (graceful fallback)
- [x] Transaction-wrapped delete to prevent TOCTOU race conditions

### 4.7.4 UI
- [x] InventoryLive.Index page at `/inventories` with table view
- [x] Create/edit/delete modals with typed confirmation for delete
- [x] Current inventory badge in navigation
- [x] Security: validated redirects, safe integer parsing

**Go/No-Go:** ✅ Multiple inventories work. 14 new tests passing.

## Phase 4.8: Backup System ✅ COMPLETE

Automated database and photo backups with full management UI.

### 4.8.1 Storage
- [x] Local file storage in `priv/backups/` (Syncthing-friendly)
- [x] Path traversal protection with safe_path/1 validation
- [x] Backup manifest with metadata (type, created_at, sizes)

### 4.8.2 Backup Operations
- [x] Database backup via pg_dump (gzipped SQL)
- [x] Photo backup (tar.gz of uploads directory)
- [x] Combined backup with both database and photos
- [x] Safe command execution (no shell injection)

### 4.8.3 Restore Operations
- [x] Full restore capability including database and photos
- [x] Pre-restore safety backup created automatically
- [x] Maintenance mode overlay during restore operations
- [x] Application restart after database restore

### 4.8.4 Scheduling
- [x] Quantum-scheduled daily and weekly backups
- [x] Configurable retention periods (daily: 7, weekly: 4)
- [x] Automatic cleanup of old backups

### 4.8.5 UI
- [x] BackupLive.Index page at `/admin/backups`
- [x] Admin toggle for accessing backup management
- [x] Create/restore/delete operations with confirmation modals
- [x] Backup list with size and date information

**Go/No-Go:** ✅ Backups work. Full restore tested. Security reviewed.

## Phase 5: ~~Multi-Device Photo Capture~~ (Removed)

Workflow changed: photos are taken in batch on phone, synced to desktop via Syncthing, then items are added on desktop using product page photos and URL fetching. PubSub real-time sync is unnecessary.

## Phase 6: Polish and Scale

### 6.1 Performance
- [x] Implement pagination for item list (page size 48, offset-based)
- [x] Add location shelf filtering (multi-select checkbox chips)
- [ ] ~~Optimize photo storage (thumbnails, compression)~~ Deferred: photos avg 109KB after existing resize pipeline (1920x1080 @ 85% JPEG). 103 photos = 12MB. Projected 1000 items = ~106MB. Revisit if page loads feel slow past 500 items.

### 6.2 Reliability
- [x] Database backup strategy (implemented in Phase 4.8)

**Go/No-Go:** ✅ Pagination and filtering complete. Photo optimization deferred (not needed at current scale). Ready for full catalogue.

## Phase 7: Full Catalogue (Ongoing)

Adding items periodically. Not a blocking development step.

- [ ] Enter all workshop items (~1000)
- [ ] Refine workflow based on friction points

---

## Phase 8: ~~Image-Based Search~~ (Deferred)

Deferred in favor of public access and marketplace features. Can revisit after Phase 10.

- Add image embedding generation (CLIP or similar)
- Store embeddings in pgvector
- Implement "search by photo" feature

## Phase 9: Auth + Public Deployment (Milestone F)

Deploy inventory to the public internet with OAuth authentication and invite-only registration.

### 9.1 Infrastructure
- [ ] Provision dedicated GCP Compute Engine VM
- [ ] Install Erlang/OTP, Elixir, PostgreSQL on VM
- [ ] Create unprivileged `inventory` user for running the application
- [ ] Configure firewall: SSH (key-auth only) + HTTP/HTTPS
- [ ] Install and configure Caddy as reverse proxy with automatic TLS
- [ ] Set up custom domain with DNS pointing to VM
- [ ] Configure Phoenix release (mix release) with systemd service
- [ ] Set up deployment workflow (git pull → build release → restart service)

### 9.2 Authentication
- [ ] Add Ueberauth with GitHub and LinkedIn strategies
- [ ] Create `users` migration (name, email, avatar_url, role)
- [ ] Create `user_identities` migration (provider, provider_uid, user_id)
- [ ] Create `invite_codes` migration (code, created_by, used_by, expires_at, used_at)
- [ ] Implement User schema and Accounts context
- [ ] Implement OAuth callback controller (create or match existing user)
- [ ] Implement invite code validation on first sign-in
- [ ] Implement session management (login/logout)
- [ ] First user auto-promoted to admin role

### 9.3 Authorization
- [ ] Add authentication plug (require login for all routes except landing page)
- [ ] Add role-based authorization (admin vs member)
- [ ] Members: read-only access to inventory (browse, search, view items)
- [ ] Admin: full access (current functionality unchanged)
- [ ] Protect admin routes (backups, inventory management, shelf CRUD, item CRUD)

### 9.4 Landing Page
- [ ] Create public landing page (description of service, sign-in buttons)
- [ ] LinkedIn and GitHub sign-in buttons
- [ ] Redirect authenticated users to inventory

### 9.5 Invite System
- [ ] Admin UI to generate invite codes (with optional expiration)
- [ ] Display active/used invite codes
- [ ] Invite code entry form shown after first OAuth sign-in
- [ ] Revoke unused invite codes

### 9.6 Security Hardening
- [ ] Content Security Policy headers
- [ ] Rate limiting on OAuth and invite code endpoints
- [ ] Audit logging for admin actions
- [ ] Review all routes for proper authorization

**Go/No-Go:** Site accessible on public URL. OAuth sign-in works. Invite-only registration enforced. Admin/member roles working.

## Phase 10: Requests + Marketplace (Milestones G-I)

Enable members to request items for borrow, lease, or sale. All transactions happen in person.

### 10.1 Listings
- [ ] Create `listings` migration (item_type_id, type, price, notes, active)
- [ ] Implement Listing schema and context functions
- [ ] Admin UI to mark items as available (borrow/lease/sale with optional price)
- [ ] Display listing info on item detail view

### 10.2 Requests
- [ ] Create `requests` migration (listing_id, requester_id, status, message, admin_notes)
- [ ] Implement Request schema and context functions
- [ ] Member UI to request an available item (with message)
- [ ] Admin UI to view, approve, deny, and complete requests
- [ ] Request status workflow: pending → approved/denied, approved → completed

### 10.3 Notifications
- [ ] Add Swoosh for email delivery
- [ ] Add Oban for async job processing
- [ ] Email admin when new request received
- [ ] Email member when request approved/denied
- [ ] In-app notification indicators (Phoenix PubSub)

### 10.4 Member Experience
- [ ] Member browse view (read-only catalog with available items highlighted)
- [ ] Member request history (my requests and their statuses)
- [ ] Member profile page

**Go/No-Go:** Members can browse inventory, request items, receive status updates. Admin can manage requests.

## Phase 11: Multi-User Inventories (Future)

Other users create and share their own inventories.

- Inventory ownership (users own inventories, not just the admin)
- Inventory sharing keys with configurable access levels
- Cross-inventory browsing and discovery
- Open registration (remove invite-code requirement)

---

## Development Approach

### Pair-Programming Style
- AI generates code, user reviews and edits
- Focus on learning Elixir patterns
- User implements key logic decisions
- AI handles boilerplate and infrastructure

### Testing Strategy
- Unit tests for context modules
- LiveView tests for critical flows
- Manual testing for UI/UX
- No excessive test coverage for MVP

### Iteration
- Complete each phase before moving on
- Go/No-Go checkpoints validate progress
- Adjust plan based on learnings
- Prioritize working software over perfect design
