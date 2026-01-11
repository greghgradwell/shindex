# Inventory Locator Service - Implementation Plan

## Overview

This plan implements the Core MVP: add items, find items, AI-powered search.

**Target:** Working system capable of cataloguing 1000+ workshop items.

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

**Go/No-Go:** Can create locations and items via IEx console. Location parser handles "a-3-0" correctly.

## Phase 2: Basic UI

**UX Decisions:**
- Search-first interface (no default list for 1000+ items)
- Hybrid workflow: phone photo capture → desktop data entry
- Inline location creation (type "A-3-0" → "Create?" → one click)
- Archive pattern: archived items stay searchable, location is freed
  - When archiving: location_id → NULL (frees location for reuse)
  - When restoring: user must assign new location before saving

**See `docs/PHASE_2_PLAN.md` for detailed strategy**

### 2.0 Schema: Archive Support
- [x] Add `archived` boolean field to item_types (indexed)
- [x] Make `location_id` nullable with bidirectional constraint:
  - Active items (archived=false) MUST have location_id
  - Archived items (archived=true) MUST have location_id=NULL (frees location)
- [x] Allow `quantity >= 0` (change from `> 0`)
- [x] Update ItemType schema with bidirectional archive validation
- [x] Add comprehensive tests for archive/restore lifecycle
- [ ] Add archive/restore functions to Inventory context (helper methods)

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

### 2.6 Polish & UX
- [ ] Responsive CSS for mobile/desktop
- [ ] Mobile-optimize camera UI (clear required field indicators)
- [ ] Desktop-optimize data entry forms (keyboard shortcuts)
- [x] Batch completion UX (progress indicator, auto-advance, auto-focus)
- [ ] Error messaging improvements
- [ ] Loading states (photo upload/downsample progress)
- [ ] "Incomplete metadata" badge styling
- [x] Archived item opacity/styling

**Go/No-Go:** Phone workflow sub-30s, batch completion efficient, search ordering correct, photos ~300KB. (Milestone A)

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

## Phase 4: AI Search

### 4.1 Python Service Setup
- [ ] Create ai_search/ directory structure
- [ ] Set up FastAPI application
- [ ] Configure VertexAI credentials
- [ ] Implement /health endpoint

### 4.2 Search Endpoint
- [ ] Implement /search POST endpoint
- [ ] Create LangChain chain for query interpretation
- [ ] Accept inventory data (or fetch from shared database)
- [ ] Return ranked item matches

### 4.3 Elixir Integration
- [ ] Create AISearch module with HTTP client
- [ ] Add AI search toggle to search UI
- [ ] Display AI results alongside text results
- [ ] Handle AI service unavailability gracefully

**Go/No-Go:** "mipi camera" query finds Raspberry Pi Camera. (Milestone C)

## Phase 5: Multi-Device Photo Capture

### 5.1 Camera LiveView
- [ ] Create CameraLive - dedicated camera capture page
- [ ] Implement browser camera access (getUserMedia)
- [ ] Capture photo and upload to server
- [ ] Generate shareable session link (same user, different device)

### 5.2 Photo Sync
- [ ] Broadcast photo via PubSub when captured
- [ ] Desktop ItemLive.New subscribes to photo channel
- [ ] Display captured photo in add item form
- [ ] Handle multiple photos (select which to use)

**Go/No-Go:** Phone captures photo, appears on desktop instantly.

## Phase 6: Polish and Scale

### 6.1 Performance
- [ ] Add database indexes for common queries
- [ ] Implement pagination for item list
- [ ] Optimize photo storage (thumbnails, compression)
- [ ] Add loading states to UI

### 6.2 UX Improvements
- [ ] Keyboard shortcuts for common actions
- [ ] Bulk location creation
- [ ] Recently added items section
- [ ] Search result highlighting

### 6.3 Reliability
- [ ] Error handling for AI service failures
- [ ] Photo upload retry logic
- [ ] Database backup strategy

**Go/No-Go:** System performs well with 100+ items. Ready for full catalogue.

## Phase 7: Full Catalogue (Milestone D)

- [ ] Enter all workshop items (~1000)
- [ ] Refine workflow based on friction points
- [ ] Document lessons learned
- [ ] Identify improvements for next iteration

---

## Future Phases (Post-MVP)

### Phase 8: Image-Based Search (Milestone E)
- Add image embedding generation (CLIP or similar)
- Store embeddings in pgvector
- Implement "search by photo" feature

### Phase 9: Public Access (Milestone F)
- Add user authentication (phx_gen_auth)
- Implement access levels (admin, friend, public)
- Deploy to public internet with HTTPS
- Security audit

### Phase 10: Sharing & Marketplace (Milestones G-I)
- Invite link generation
- Borrow request workflow
- Purchase offer workflow
- Notifications

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
