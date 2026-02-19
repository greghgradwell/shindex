# Inventory Locator Service - Specification

## Vision

A personal inventory system that enables users to:
1. Track every item they own with precise location information
2. Find items instantly, even with vague or semantic queries
3. Share inventory with others for borrowing, lending, or selling

**Long-term goal:** Reduce consumption by making borrowing/lending frictionless. Open-source or public product.

## Problem Statement

Workshop and household items are difficult to locate, leading to:
- Wasted time searching for items (minutes per search)
- Duplicate purchases of items already owned
- Missed project deadlines waiting for reordered parts
- No mechanism to share/lend items efficiently

## Users

### Primary User (MVP)
- **Workshop owner** with 1000+ items across 200+ storage locations
- Needs to add items quickly during workshop organization
- Searches for items by name, description, or semantic meaning

### Secondary Users
- **Inventory owners** - Invited users who create and manage their own inventories
- **Viewers** - Users granted read-only access to an inventory via one-time share codes
- **Members** - Invited users who can browse shared inventories and request items for borrow/lease/sale (Phase 10)

## Core Requirements

### Location Management
- **Hierarchy:** Shelf → Bin
- **Naming:** Short codes preferred (e.g., "A-3" for Shelf A, Bin 3)
- **Co-location:** Multiple items can share a location (user warned but allowed)
- **Flexibility:** Locations can be created on-the-fly during item entry

### Location Entry (String-Based)
- User types location as string (e.g., "a-3")
- System normalizes and validates (e.g., "a-3" → "A-3")
- If location exists and is empty: confirm and use
- If location exists and is occupied: warn user, but allow co-location
- If location does not exist: prompt to create (e.g., "Shelf A has 2 bins. Create bin 3?")
- No dropdown menus required - string entry is faster for high-volume data entry

### Item Management
- **Required fields:** Name, photo, location, quantity, archived status
- **Optional fields:** Description, manufacturer, model
- **Photos:** Uploaded from file or fetched from product page URL
- **Co-location:** Multiple items can share a location (user warned but allowed)
- **Projects:** Items can be installed in named projects, reducing available stock
- **Constraint:** Active items MUST have a valid location
  - With chaotic storage, a lost location = lost item
  - Database enforces: `(archived=false AND location_id IS NOT NULL)`
  - Location deletion blocked if active item exists at that location
- **Archive Pattern:** Items with quantity=0 or no longer needed
  - Archiving frees the location: `location_id` → `NULL`
  - Archived items remain searchable but don't occupy a location
  - Restoring requires assigning a new valid location before saving
  - Database enforces: `(archived=true AND location_id IS NULL)`

### Project Tracking
- **Purpose:** Track items installed in project builds
- **Workflow:** Install items to named project, reducing available stock
- **Visibility:** Projects page shows all active projects with components
- **Dismantling:** Return all items from project to stock
- **Constraint:** Cannot dismantle project with archived items (must restore first)

### Duplicate Detection
- System suggests possible duplicates when adding new items
- User decides whether to merge, skip, or create new
- "Definitely new" fast path available to skip duplicate check
- Duplicates are semantic (XT-60 connectors from any manufacturer = same item type)

### Search
- **Text search:** Fast, typo-tolerant (fuzzy matching)
- **AI search:** Natural language queries interpreted by LLM
  - Example: "mipi camera" finds "Raspberry Pi Camera Module v2" with MIPI CSI-2 connector
- **Results:** Return item name, location code, photo thumbnail, quantity

### Workflow
- Desktop-first data entry with full keyboard and screen
- Photos taken in batch on phone, synced to desktop via Syncthing
- Product page photos fetched via URL for professional-grade images
- Items created from Browse or Locations pages via modal

## Success Criteria

### Core MVP (Must Have)
| ID | Criterion | Validation |
|----|-----------|------------|
| A | Add an item, then find it via search | Manual test |
| B | Duplicate detection suggests existing item | Manual test |
| C | Fuzzy/AI search finds item with vague query | "mipi camera" test |
| D | Full workshop catalogued | 1000+ items entered |

### Data Integrity (Invariants)
| ID | Invariant | Enforcement |
|----|-----------|-------------|
| X1 | No orphaned items (every active item has a valid location) | Conditional NOT NULL, block location deletion if occupied |
| X2 | Co-location warnings | User warned when placing item in occupied location (no unique constraint) |
| X3 | Location hierarchy valid (bin belongs to shelf, etc.) | Foreign key constraints |

### Expanded MVP
| ID | Criterion | Validation |
|----|-----------|------------|
| E | Find item by taking its picture | Image → search works |

### Public Release
| ID | Criterion | Validation |
|----|-----------|------------|
| F | Inventory accessible on open web (securely) | HTTPS, OAuth working, invite-only |
| G | Invite a user with invite code | Code grants account creation |
| H | Receive borrow/lease request through system | End-to-end request flow works |
| I | Receive purchase inquiry through system | End-to-end request flow works |

## Non-Functional Requirements

### Performance
- Add item workflow: < 30 seconds per item (target: 20 seconds)
- Text search: < 100ms response time
- AI search: < 3 seconds response time

### Scale
- 1000+ items for MVP
- 10,000+ items for household expansion
- Multiple concurrent users for public release

### Authentication & Access
- **OAuth only:** LinkedIn and GitHub (no email/password). Real identities reduce anonymity.
- **Invite-only registration:** Users need an invite code to create an account. Open registration planned for later.
- **Roles:**
  - **Admin:** Site-level control (generate invite codes, manage backups). First user is auto-admin.
  - **Owner:** Per-inventory control. Each inventory belongs to a user. Owners can create/edit/delete their inventories and share them.
  - **Viewer:** Read-only access to shared inventories. Cannot modify items, locations, or projects.
- **Sharing:** Owners generate one-time-use share codes (7-day expiry). Another user redeems a code to gain viewer access to that inventory.
- **Anonymous visitors:** See landing page only. Must sign in to access any inventory data.

### Security
- Dedicated GCP VM (no shared workloads) with firewall, SSH key-auth only
- Reverse proxy (Caddy) with TLS termination, only ports 80/443 exposed
- Unprivileged application user with no access to host files beyond app directory
- Dedicated PostgreSQL user scoped to inventory database only
- OAuth eliminates password storage attack surface
- Invite-only registration limits account creation to known users

## Out of Scope (MVP)

- Payment processing (prices displayed, all transactions in person)
- Rental term management ($/hour, $/week)
- Mobile native app (web responsive is sufficient)
- Barcode/QR code scanning (future consideration)
- Automatic reorder suggestions
- Email/password authentication (OAuth only)
- Open registration (invite-only for now)
- Cross-inventory discovery
