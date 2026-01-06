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
- [x] Implement Inventory context (CRUD operations)
- [x] Write tests for core operations

### 1.4 Location Code Parser
- [ ] Implement location code parser ("a3-0" → {shelf: "A", bin: "3", cell: "0"})
- [ ] Handle case normalization
- [ ] Validate parsed result against existing hierarchy
- [ ] Return status: :exists_empty, :exists_occupied, :needs_creation
- [ ] Write tests for parsing edge cases

**Go/No-Go:** Can create locations and items via IEx console. Location parser handles "a3-0" correctly.

## Phase 2: Basic UI

### 2.1 Location Management
- [ ] Create LocationLive.Index - list locations grouped by shelf/bin
- [ ] Add shelf creation UI
- [ ] Add bin creation UI (select shelf)
- [ ] Add cell creation UI (select bin)
- [ ] Display full location codes (e.g., "A3-0")
- [ ] Add location editing/deletion with cascade warnings

### 2.2 Item List and Detail
- [ ] Create ItemLive.Index - list all items with search box
- [ ] Create ItemLive.Show - item detail view
- [ ] Display photo, name, location, quantity
- [ ] Add quantity increment/decrement controls

### 2.3 Add Item Flow
- [ ] Create ItemLive.New - add item form
- [ ] Implement photo upload (file input)
- [ ] String-based location entry with real-time validation
- [ ] Show location status (valid/occupied/needs creation)
- [ ] Prompt to create location if it doesn't exist
- [ ] Block save if location is occupied
- [ ] Save item and redirect to list

**Go/No-Go:** Can add item with photo and find it in list. (Milestone A)

## Phase 3: Search

### 3.1 Text Search
- [ ] Implement full-text search in Inventory context
- [ ] Add trigram similarity fallback for typo tolerance
- [ ] Wire search box to LiveView with debounce
- [ ] Display results with relevance ordering

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
