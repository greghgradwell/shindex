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

### Secondary Users (Post-MVP)
- **Household members** - Co-administrators who can add/remove/locate items
- **Friends** - Read-only access to full or filtered inventory
- **Public** - Browse items marked for sale/borrow

## Core Requirements

### Location Management
- **Hierarchy:** Shelf → Bin → Cell
- **Naming:** Short codes preferred (e.g., "A-3-0" for Shelf A, Bin 3, Cell 0)
- **Constraint:** Each location holds exactly ONE item type
- **Flexibility:** Locations can be created on-the-fly during item entry

### Location Entry (String-Based)
- User types location as string (e.g., "a-3-0")
- System normalizes and validates (e.g., "a-3-0" → "A-3-0")
- If location exists and is empty: confirm and use
- If location exists and is occupied: alert user (collision)
- If location does not exist: prompt to create (e.g., "Shelf A has 2 bins. Create bin 3?")
- No dropdown menus required - string entry is faster for high-volume data entry

### Item Management
- **Required fields:** Name, photo, location, quantity, archived status
- **Optional fields:** Description, manufacturer, model
- **Photos:** Captured from phone camera or desktop webcam
- **Constraint:** One item type per location (enforced by system)
- **Constraint:** Active items MUST have a valid location
  - With chaotic storage, a lost location = lost item
  - Database enforces: `(archived=false AND location_id IS NOT NULL)`
  - Location deletion blocked if active item exists at that location
- **Archive Pattern:** Items with quantity=0 or no longer needed
  - Archiving frees the location: `location_id` → `NULL`
  - Archived items remain searchable but don't occupy a location
  - Restoring requires assigning a new valid location before saving
  - Database enforces: `(archived=true AND location_id IS NULL)`

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

### Multi-Device Workflow
- Web UI works on desktop and mobile browsers
- Phone captures photo → instantly appears on desktop session
- Same user, two devices, real-time sync

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
| X1 | No orphaned items (every item has a valid location) | NOT NULL constraint, block location deletion if occupied |
| X2 | One item type per location | UNIQUE constraint on location_id |
| X3 | Location hierarchy valid (bin belongs to shelf, etc.) | Foreign key constraints |

### Expanded MVP
| ID | Criterion | Validation |
|----|-----------|------------|
| E | Find item by taking its picture | Image → search works |

### Public Release
| ID | Criterion | Validation |
|----|-----------|------------|
| F | Inventory accessible on open web (securely) | HTTPS, auth working |
| G | Invite friend with custom access link | Link grants correct access |
| H | Receive borrow request through system | End-to-end flow works |
| I | Receive purchase offer through system | End-to-end flow works |

## Non-Functional Requirements

### Performance
- Add item workflow: < 30 seconds per item (target: 20 seconds)
- Text search: < 100ms response time
- AI search: < 3 seconds response time

### Scale
- 1000+ items for MVP
- 10,000+ items for household expansion
- Multiple concurrent users for public release

### Security (Post-MVP)
- Authentication required for modifications
- Access levels: Admin, Friend, Public
- Secure invite links (time-limited, single-use option)

## Out of Scope (MVP)

- Payment processing
- Rental term management ($/hour, $/week)
- Mobile native app (web responsive is sufficient)
- Barcode/QR code scanning (future consideration)
- Automatic reorder suggestions
