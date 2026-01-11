# Phase 2: Basic UI - Strategy & Implementation Plan

## Overview

Implement the core user interface for the inventory system based on UX decisions:
- **Hybrid workflow**: Phone captures photos → Desktop handles full data entry
- **Search-first interface**: No overwhelming lists, query-driven discovery
- **Inline location creation**: Zero friction when typing non-existent locations
- **Archive pattern**: Items with qty=0 stay in system but marked as archived

## UX Requirements

### User Workflows

#### 1. Add Item (Primary Use Case)
**Hybrid Approach:**
1. **Phone Session**: User walks workshop taking photos with mobile camera interface
   - **Required fields**: Name, location code
   - **Optional fields**: Description, manufacturer, model, quantity (defaults to 1)
   - Photos captured with auto-downsampling (see Photo Management below)
   - Photos upload and broadcast via PubSub
   - Saves item immediately (incomplete metadata ok)
2. **Desktop Session**: Batch completion workflow
   - Filter items by missing fields (e.g., "show all items missing manufacturer")
   - Complete metadata for multiple items in sequence
   - Full keyboard-optimized forms with tab navigation
   - Synced photos displayed for reference

**Success Metric**: Sub-30-second workflow per item on phone (target: 20s), efficient batch completion on desktop

#### 2. Find Item
**Search-First Interface:**
- Landing page shows search box, no default list (avoids 1000+ item pagination)
- Type to search with debounced results
- **Result ordering**: In-stock items first, then archived items
- **Result styling**: Archived items displayed with reduced opacity (visually distinct)
- Results display: photo thumbnail, name, location code, quantity, archived badge
- Click result navigates to detail view

#### 3. Modify Item
- Search → detail view → edit mode
- Update: quantity, location, description, photo
- Quantity adjustment: increment/decrement buttons
- Quantity→0 triggers archive flow (frees location, item stays searchable)

#### 4. Archive/Restore Items
- **Archive**: When qty→0, set archived=true, clear location_id (frees location)
- **Restore**: Requires new location assignment + quantity>0, clears archived flag
- Archived items shown in search results with badge (hidden by default, toggle to show)
- Rationale: Never delete items, might purchase again later

#### 5. Batch Completion Workflow (Desktop)
**Purpose**: Complete metadata for items added quickly on phone

**Workflow**:
- Use filter checkboxes on home page (`/`) to show incomplete items
- Filter by missing field: "Show items missing manufacturer"
- Display filtered items in grid view
- Click item → modal opens directly in edit mode → complete metadata → save
- Auto-advance to next incomplete item after save
- "All items complete!" message when batch is finished

**Filters Available**:
- Missing manufacturer
- Missing model
- Missing description

**Why**: Separates fast capture (phone) from detailed cataloging (desktop keyboard)

#### 6. Manage Locations
- View locations grouped by shelf→bin→cell hierarchy
- Display occupied vs empty status for each location
- Delete empty locations (show cascade warning if has children)
- Block deletion of occupied locations (must remove/archive item first)

#### 7. Photo Management
**Downsampling Strategy**:
- Phone cameras produce high-resolution images (Pixel 9a: 64MP, ~15-20MB per photo)
- 1000 items at full resolution = ~15-20GB storage
- **Solution**: Downsample on upload to max 1920x1080 (1080p), ~300KB per photo
- 1000 items downsampled = ~300MB storage (50-60x reduction)
- Quality sufficient for item identification, dramatic storage savings

**Technical Approach**:
- Server-side downsampling on upload (ImageMagick or Elixir library)
- Preserve aspect ratio, optimize JPEG quality (~85%)
- Optional: Keep original filename reference for future re-processing

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Search-first interface** | Scales to 1000+ items without pagination, encourages specific queries |
| **In-stock items first, then archived** | Active inventory prioritized in search results, archived items visually distinct (reduced opacity) |
| **Inline location creation** | User types "A-3-0", sees "doesn't exist → Create?", clicks once, continues. Zero context switching. |
| **Archive pattern** | Depleted items remain searchable (purchase history), location freed for new items, can restock later |
| **Hybrid entry workflow** | Phone excels at photo capture, desktop excels at detailed data entry |
| **Phone requires name + location** | Minimal required fields enable fast capture, optional fields completed later on desktop |
| **Batch completion workflow** | Filter by missing fields, complete metadata in batches, keyboard-optimized |
| **Photo downsampling** | Server-side resize to 1080p (~300KB) prevents storage bloat (50-60x reduction from 64MP originals) |

## Technical Strategy

### 2.0 Schema Changes: Archive Support

**Goal**: Support zero-quantity items without requiring location

**Approach**:
1. Add `archived` boolean field to `item_types` table (default: false, indexed)
2. Make `location_id` nullable in `item_types` table
3. Add database constraint: `(archived = true) OR (location_id IS NOT NULL)`
   - **Enforces**: Active items MUST have location, archived items can be locationless
4. Change `quantity` validation from `> 0` to `>= 0` (allow zero for archived)
5. Update `ItemType` schema validations to mirror database constraints

**Why**:
- Database-level integrity prevents orphaned active items
- Archived items don't block location reuse
- Clear separation: active (has location + qty>0) vs archived (no location + qty=0)

### 2.05 Inventory Context Enhancements

**Add archive/restore operations**:
- `archive_item_type(item)`: Sets qty=0, archived=true, location_id=nil
- `restore_item_type(item, %{location_id: ..., quantity: ...})`: Clears archived, assigns location, sets qty
- `list_active_item_types()`: Filter for archived=false
- `list_archived_item_types()`: Filter for archived=true
- `get_item_type_with_location!(id)`: Preload location with shelf/bin/cell for detail views

**Why**: Clear API for archive lifecycle, filtering active vs archived

### 2.1 Location Management LiveView

**Module**: `LocationLive.Index`

**Purpose**: View/manage location hierarchy, see occupied vs empty status

**Strategy**:
- Query all locations with preloaded shelf/bin/cell/item relationships
- Group results hierarchically: shelf → bins → cells → locations
- Display occupation status (occupied shows item name, empty shows delete button)
- Handle delete events (validate empty before deletion)

**Why**: Spatial view of storage system, manage empty locations

### 2.2 Item Search Interface

**Module**: `ItemLive.Index`

**Purpose**: Search-first landing page with filtering

**Strategy**:
- Mount with empty state (query="", results=[])
- Debounce search input (300ms)
- Query items with pg_trgm fuzzy search (trigram similarity > 0.3 for typo tolerance)
- **Result ordering**: ORDER BY similarity DESC (most relevant first), archived ASC, then name
- Toggle for showing/hiding archived items (default: hidden)
- **Checkbox filters**: "Missing manufacturer", "Missing model", "Missing description" (OR logic)
- **Visual styling**: Archived items rendered with `opacity-50` (less prominent)
- Display results in photo grid with metadata
- Link to detail view or edit form on click

**Why**: No overwhelming default list, instant feedback, batch completion workflow, scales to large datasets, typo tolerance

**Implementation Note**: Originally planned with ILIKE for Phase 2 and fuzzy search for Phase 3, but implemented fuzzy search directly in Phase 2.2 since pg_trgm index already existed from Phase 1.2.

### 2.3 Item Detail View (Modal)

**Module**: `ItemLive.ShowModal` (LiveComponent, replaces `ItemLive.Show` page)

**Purpose**: Full item details with quantity controls and archive/restore, displayed as modal overlay

**Strategy**:
- LiveComponent with `update/2` callback to load item data when `item_id` changes
- Preload item with location hierarchy and installations
- Quantity controls: increment/decrement buttons
- When qty decrements to 0: trigger archive flow (confirmation UI)
- For archived items: show "Restore" button → restore flow (assign location + qty)
- Move-to-location form for relocating items
- Install/uninstall items to/from projects
- Close via ESC key, click-outside, or X button
- Parent LiveView manages `selected_item_id` state

**Why**: Modal keeps user in search context, eliminates page navigation overhead, supports "< 30s per item" goal

### 2.4 Add Item Flow (Hybrid Workflow)

#### Phone: Camera Capture + Quick Entry

**Module**: `CameraLive.Index`

**Purpose**: Mobile-optimized photo capture with immediate item creation

**Strategy**:
- Generate session_id on mount (for PubSub channel)
- Display session_id or QR code for desktop pairing
- Use HTML5 `getUserMedia()` API for camera access
- Capture photo → downsample on server → save → broadcast filename via PubSub
- **Entry form with required fields**:
  - Name (required, text input)
  - Location code (required, validated via LocationParser)
  - Inline location creation if needed
- **Optional fields**: description, manufacturer, model, quantity (default: 1)
- Save immediately after photo + required fields entered
- Show saved items in local list with "incomplete metadata" badge if optional fields missing

**Photo Processing**:
- Upload original photo to server
- Server downsamples to max 1920x1080, ~85% JPEG quality
- Save downsampled version (~300KB), optionally keep original filename reference
- Broadcast downsampled filename to desktop

**Why**: Fast capture with minimal required data, server handles image optimization, items saved immediately

#### Desktop: Batch Completion ✅ COMPLETE

**Module**: `ItemLive.Index` + `ItemLive.ShowModal`

**Purpose**: Complete metadata for items added on phone

**Implementation (Completed)**:
- Use filter checkboxes on home page (`/`) to show incomplete items
- Filter by missing field (manufacturer, model, description)
- Click item → modal opens directly in edit mode (`batch_mode=true`)
- First empty field auto-focused (`FocusFirstEmpty` JS hook)
- Complete missing fields, click "Save & Next"
- `ShowModal` sends `{:advance_to_next_incomplete}` to parent `Index`
- `Index` re-runs search, advances modal to next incomplete item
- Form state properly reset (dynamic form IDs include `@item.id`)
- "All items complete!" flash message when batch finished

**Why**: Keyboard-optimized, batch workflow for completing metadata, modal keeps user in search context

#### Desktop: Full Entry (Pending)

**Module**: `ItemLive.New`

**Purpose**: Add new items from desktop with full form

**Strategy**:
- Full form with all fields (name, location, description, manufacturer, model, quantity)
- Location input field with real-time validation
- Inline location creation button
- Photo upload with downsampling
- Save creates complete item

### 2.5 Router Configuration

**Routes**:
- `/` → Search interface (search-first with filters, batch completion via modal)
- `/locations` → Location management (hierarchical view)
- `/projects` → Projects management
- `/camera` → Photo capture + quick entry (mobile)

**Design decisions**:
- No `/items/*` routes - all item operations happen via modal overlay from search/projects pages
- Batch completion integrated into home page via filter checkboxes + auto-advancing modal
- Simplified routing reduces navigation overhead

**Why**: Modal approach eliminates need for dedicated item routes, keeps user in search context

## Data Flow

### Photo Sync Flow (Simplified - No PubSub)
1. Phone: Capture photo → Upload to server with item data
2. Server: Downsample to 1920x1080, ~85% JPEG quality → Save to `priv/static/uploads/` (~300KB)
3. Server: Save item with photo path
4. Desktop: Refresh page to see new items (no real-time PubSub sync)
5. Desktop: Use batch completion workflow to fill in remaining metadata

### Location Validation Flow
1. User types location code (e.g., "A-3-0")
2. Parse: Split on `-`, validate shelf/bin/cell components
3. Validate: Check database hierarchy (LocationParser)
4. Return status: `:exists_empty` / `:exists_occupied` / `:needs_creation`
5. UI response:
   - Valid → enable save
   - Occupied → show error
   - Needs creation → show inline creation button

### Archive Flow
1. User decrements quantity to 0 (or edits qty field)
2. Trigger archive: Set archived=true, location_id=nil, quantity=0
3. Update location: Now available for new items
4. Update UI: Show archived badge, remove from default search

### Restore Flow
1. User clicks "Restock" on archived item
2. Show form: location input + quantity input
3. Validate location (same flow as new item)
4. Save: Set archived=false, location_id=validated_location, quantity=new_qty

### Batch Completion Flow ✅ IMPLEMENTED
1. On home page (`/`), check filter checkbox (e.g., "Missing manufacturer")
2. Query: `WHERE manufacturer IS NULL AND archived = false`
3. Display results in grid
4. Click item → modal opens directly in edit mode (batch_mode=true)
5. First empty field is auto-focused (FocusFirstEmpty JS hook)
6. Enter metadata, click "Save & Next" (or press Enter)
7. `ShowModal` saves item, sends `{:advance_to_next_incomplete}` to parent
8. `Index` re-runs search query, advances to first remaining item
9. Modal stays open with new item, form state reset, first empty field focused
10. Repeat until "All items complete!" flash message appears

## Testing Strategy

### Unit Tests (Ecto)
- `ItemType` changeset validation with archived scenarios
- `Inventory` context: archive/restore operations
- Location creation from missing hierarchy

### LiveView Tests
- Search flow: query → results (ordered: in-stock first) → click
- Search filters: missing manufacturer/model/description
- Location validation: parse → validate → status
- Inline creation: needs_creation → create → valid
- Archive flow: qty→0 → archived
- Restore flow: restock → assign location
- Batch completion: filter → edit → auto-advance

### Manual Testing (End-to-End)
- Full hybrid workflow: phone photo + name/location → save → desktop batch completion
- Photo downsampling: verify 64MP Pixel 9a photo → ~300KB output
- Search with 10+ items, toggle archived, verify ordering
- Archived items have reduced opacity
- Location collision handling
- Archive/restore round-trip
- Batch completion with keyboard shortcuts

## Dependencies

**New dependency required**:
- **Image processing library**: `image` v0.62+ (libvips-based, precompiled binaries)
  - Purpose: Server-side photo downsampling (resize to 1920x1080, optimize JPEG)
  - Performance: 2-3x faster than mogrify, 5x less memory usage
  - Installation: No system dependencies required (precompiled binaries included)

**Existing dependencies**:
- Phoenix LiveView (real-time UI, batch completion workflow)
- Ecto (database operations)

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Inline location creation confusing | Clear messaging: "Location A-3-0 doesn't exist. Create shelf A, bin 3, cell 0?" |
| Search slow with 1000+ items | Phase 3 adds indexes + fuzzy search, Phase 6 optimizes queries |
| Archived items clutter results | Default to hidden, require explicit toggle, render with reduced opacity |
| Users forget to archive on depletion | Auto-archive when qty edited to 0, show confirmation |
| Photo downsampling too aggressive | Test with real Pixel 9a photos, adjust quality/resolution if needed |
| Photo processing slows uploads | Async job processing (optional), or accept slight delay for 50-60x storage savings |
| Incomplete items forgotten | Badge in search results, filter checkboxes prominent on home page, batch completion workflow |

## Implementation Order

### Phase 2.0: Schema Updates (Foundation)
**Deliverables**:
- 3 migrations: add `archived`, make `location_id` nullable, allow `quantity >= 0`
- Updated `ItemType` schema with archive validation
- Archive/restore functions in `Inventory` context
- Tests for archive/restore logic

**Go/No-Go**: Archive item via IEx → location freed, can restore with new location.

---

### Phase 2.1: Location Management UI ✅ COMPLETE

**Visual Design**: Gantt-chart style display (railway timetable layout)
- Each shelf displayed as horizontal row spanning full width
- Bins displayed as labeled segments/rectangles within shelf row
- Cells displayed as subdivisions within bin segments
- Proportional sizing: bin width proportional to cell count

**Interactions**:
- **Click occupied location**: Show modal quickview (photo, name, description, quantity)
- **Click "View Full Details" in modal**: Navigate to full ItemLive.Show page
- **Empty locations**: Visual distinction (badge/color) with delete button
- **Show only created locations**: Filter to locations that exist in database (not theoretical)

**Key Design Decisions**:
- **Gantt layout**: Visual hierarchy makes Shelf → Bin → Cell relationships immediately clear
- **Proportional sizing**: Bin width reflects cell count (more cells = wider bin), compact display shows 50+ locations on screen
- **Click for quickview pattern**: Click cell shows modal quickview (mobile-friendly, no hover needed), modal button navigates to full details
- **Preload full hierarchy**: Single query with nested preloads (`shelf → bins → cells → locations → item_type`) avoids N+1
- **CSS Flexbox + Grid**: Flexbox for horizontal shelf layout, Grid for cell arrangement within bins
- **Filter cells**: Only render cells with `location` record using `<%= if cell.location do %>` to avoid showing theoretical locations

**Context Functions** (all with @spec):
- `list_shelves_with_hierarchy/0`: Returns shelves with preloaded `bins → cells → locations → item_type`
- `delete_empty_location/1`: Validates empty before deletion, returns `{:ok, location}` or `{:error, :occupied}`
- `count_locations_by_occupancy/0`: Returns `%{occupied: integer, empty: integer}` for stats display

**Deliverables**:
- `LocationLive.Index` with hierarchical Gantt-chart display
- `LocationLive.Components` with `shelf_row/1`, `bin_segment/1`, `cell_box/1`, `quickview_modal/1`
- Occupied vs empty status indicators (color coding, icons)
- Click-to-show quickview modal with photo/name/description/quantity
- "View Full Details" button navigates to ItemLive.Show
- Delete empty locations (block if occupied, data-confirm dialog)
- Route: `live "/locations", LocationLive.Index`
- Unit tests for context functions
- LiveView tests for hierarchy display and deletion
- **All functions must have @spec annotations** (per CLAUDE.md coding guidelines)

**Status**: ✅ Complete
- Gantt-chart layout implemented with flexbox
- Click-to-show quickview modal displays photo/name/description/quantity
- "View Full Details" button navigates to item details (route warning - ItemLive.Show not yet implemented)
- Delete empty locations with data-confirm dialog (blocks if occupied)
- Occupancy stats display (X occupied, Y empty)
- All context functions have @spec annotations
- Tests passing (81 tests)
- Note: Originally planned with hover, switched to click (mobile-friendly, no LiveView hover support)

**Note**: Inventory context refactored - deleted 24 unused CRUD functions, final public API: 7 functions (77% reduction)

---

### Phase 2.2: Search Interface with Filtering ✅ COMPLETE
**Deliverables**:
- `ItemLive.Index` with search box
- Debounced search with pg_trgm fuzzy matching (handles typos: "scres" → "screws")
- **Result ordering**: Similarity score first, then in-stock (ORDER BY similarity DESC, archived ASC)
- **Visual styling**: Archived items with reduced opacity (CSS: opacity-50)
- Archived items toggle (default hidden)
- **Checkbox filters**: Missing manufacturer, missing model, missing description (OR logic)
- Grid result view with photos (placeholder icon for missing photos)
- Tests for search flow and filtering (26 new tests, 107 total passing)

**Status**: ✅ Complete
- Fuzzy search implemented directly (pg_trgm trigram similarity > 0.3)
- Phase 3.1 obsolete - fuzzy search already done
- All 107 tests passing
- Search-first interface (empty by default, requires query or filter)
- Multiple filters can be active (OR logic for batch completion workflow)

**Go/No-Go**: ✅ Can search items by name with typo tolerance, see most relevant first, filter by missing fields, archived items visually distinct.

---

### Phase 2.3: Item Detail View (Modal) ✅ COMPLETE

**Implementation**:
- ✅ `ItemLive.ShowModal` LiveComponent with full item display
- ✅ Quantity increment/decrement controls
- ✅ Archive confirmation when qty→0
- ✅ Restore form for archived items
- ✅ Move-to-location functionality
- ✅ Install/uninstall to projects functionality
- ✅ Removed `/items/:id` route (modal-only access)
- ✅ Wired to ItemLive.Index, LocationLive.Index, ProjectLive.Index

**Why Modal?** Eliminates page navigation, keeps user in search context, faster workflow aligned with "< 30s per item" goal.

**Go/No-Go**: ✅ Click item → modal opens → all actions work → ESC/click-outside closes.

---

### Phase 2.4: Add Item Flow (Hybrid Workflow)

#### 2.4a: Batch Completion Mode ✅ COMPLETE

**Deliverables**:
- ✅ `ItemLive.Index` tracks batch mode state (`batch_mode`, `batch_item_ids`)
- ✅ Auto-enter edit mode when filters are active
- ✅ Auto-advance to next incomplete item on save (via `{:advance_to_next_incomplete}` message)
- ✅ Progress indicator ("X remaining") in modal header
- ✅ Dynamic form IDs (`item-details-form-#{@item.id}`) for proper state reset
- ✅ `FocusFirstEmpty` JavaScript hook for auto-focusing first empty field
- ✅ "All items complete!" flash message when batch is finished

**Implementation Notes**:
- Parent `Index` LiveView manages batch state, passes to `ShowModal` component
- `ShowModal` sends `{:advance_to_next_incomplete}` to parent after successful save
- `FocusFirstEmpty` hook requires 50ms setTimeout due to LiveView DOM morph timing
- Hook re-queries DOM for fresh input reference (original becomes stale after morph)

#### 2.4b: Photo Capture & Desktop Entry ✅ COMPLETE

**Deliverables**:
- ✅ **Photo processing**: `image` dependency (~0.62), `Media.ex` downsamples to 1920x1080 at 85% JPEG
- ✅ `CameraLive.Index` for mobile photo capture + quick entry
  - ✅ **Required fields**: name, location (with inline creation via `ensure_location_with_code`)
  - ✅ **Optional fields**: description, manufacturer, model, quantity (toggle to expand)
  - ✅ Save immediately after photo + required fields
  - ✅ Recently saved items shown in session
- ✅ Photo upload + downsample (no PubSub - refresh page to see new items)
- ✅ Location input with GhostAutocomplete + co-location warnings
- ✅ Inline location creation (automatic via `ensure_location_with_code`)

**Implementation Notes**:
- `Media.process_and_save_photo/2` handles binary → resize → save to `priv/static/uploads/`
- CameraLive uses auto_upload for immediate photo processing
- Location codes are autocompleted from existing locations
- New locations created automatically when user enters unknown code

**Go/No-Go**: ✅ Phone captures photo + name/location → saves immediately → refresh page to see on desktop → batch complete remaining metadata. Photos downsampled to ~300KB. (**Milestone A from PLAN.md**)

---

### Phase 2.5: Polish & UX Refinement
**Deliverables**:
- [ ] Responsive CSS for mobile/desktop
- [ ] Mobile-optimized camera UI (full-screen, large buttons, clear required field indicators)
- [ ] Desktop-optimized forms (keyboard shortcuts, tab order)
- [x] Batch completion UX (progress indicator, auto-advance, auto-focus first empty field)
- [ ] Error message improvements
- [ ] Loading states for async operations (photo upload/downsample progress)
- [ ] "Incomplete metadata" badge styling
- [x] Archived item opacity/styling (CSS opacity-50)

**Go/No-Go**: Full workflow achieves sub-30s per item on phone, batch completion efficient on desktop, all visual distinctions clear.

---

## Success Criteria

**Milestone A Completion** (from PLAN.md):
- ✅ Add item with photo via hybrid workflow (phone: photo + name/location → desktop: batch complete metadata)
- ✅ Phone workflow achieves sub-30s per item (CameraLive with minimal required fields)
- ✅ Desktop batch completion filters by missing fields, auto-advance + auto-focus work
- ✅ Find item via search interface with fuzzy matching (typo tolerance, in-stock first, archived visually distinct)
- ✅ Location validation with inline creation (GhostAutocomplete + ensure_location_with_code)
- ✅ Archive pattern preserves purchase history (location freed for reuse)
- ✅ Photos downsampled to ~300KB (Media.ex: 1920x1080, 85% JPEG quality)
- ✅ System handles 100+ items without performance issues (fuzzy search with pg_trgm index)

**🎉 Milestone A is COMPLETE!**

## Next Phases

**Phase 3**: Search Enhancements
- ~~pg_trgm fuzzy matching for typo tolerance~~ ✅ Complete (implemented in Phase 2.2)
- ~~Search result ranking~~ ✅ Complete (similarity-based ordering in Phase 2.2)
- Duplicate detection on item add (Phase 3.2)

**Phase 4**: AI Search Integration
- Python FastAPI service
- LangChain semantic query interpretation
- "mipi camera" → finds "Raspberry Pi Camera Module v2"

**Phase 5**: Multi-Device Enhancements
- QR code session pairing
- Multiple photos per item
- Photo management (delete, reorder)
