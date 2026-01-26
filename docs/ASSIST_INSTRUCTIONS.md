# Inventory Assist Instructions

Instructions for Claude Code to assist with completing missing inventory item details.

## IMPORTANT: Start Immediately

**Do NOT ask the user questions before starting.** Assume:
- Phoenix server is running at localhost:4000
- User has /dev/assist open in browser
- Default batch size is 20

**Just run Step 1 immediately when the user asks to start assist mode.**

**Minimize chat commentary.** The UI shows status. Only speak when:
- Starting a new batch: "Sent X items to browser."
- All complete: "✅ All items complete!"
- Errors occur

**Do NOT:**
- Ask "want another batch?" (auto-loop if items remain)
- Announce "research complete" (UI shows this)
- Narrate each step (scripts handle flow)
- Comment on or summarize update results (just run them)

## Quick Reference - Execute In Order

**IMPORTANT: Follow these steps exactly. Do NOT ask for confirmation between steps.**

```
STEP 1: ./scripts/assist-batch 20
        → Tell user: "Sent X items to browser."
        → IMMEDIATELY run Step 2 (do NOT wait for user to confirm in chat)

STEP 2: ./scripts/assist-poll 300
        → BLOCKS until user clicks "Start Research" in browser
        → Do NOT ask user to confirm in chat - the script detects the button click
        → Returns JSON with items and which fields to find/skip

STEP 2b: For items where user unchecked ALL fields (nothing to find):
         ./scripts/assist-skip <id> '["field1","field2"]'
         → Persists skip to database, item won't appear in future batches
         → IMPORTANT: Only use when item.find is empty AND item.skip has values

STEP 3: For EACH item needing research:
        a) curl -s 'http://localhost:4000/api/assist/items/<id>'
           → Check if source_url is populated
        b) IF source_url exists:
              Use mcp__tavily__tavily_extract with the URL
           ELSE:
              Use mcp__tavily__tavily_search (synchronous)
        c) ./scripts/assist-batch-review <id> '{"field":"value"}'
           → Send suggestions as each search completes
        (Can run searches in parallel, send suggestions as they complete)

STEP 4: ./scripts/assist-batch-review-ready
        → Browser shows ALL items with suggestions on one page
        → IMMEDIATELY run Step 5 (do NOT wait for user to confirm in chat)

STEP 5: ./scripts/assist-batch-review-poll 600
        → BLOCKS until user clicks "Save All" in browser
        → Do NOT ask user to confirm in chat - the script detects the button click
        → Returns ALL accepted values at once

STEP 6: For each item in accepted:
        ./scripts/assist-update <id> '<accepted_json>'
        → Apply the accepted values
        → Do NOT show results to user - run silently and move to Step 7

STEP 7: count=$(curl -s "http://localhost:4000/api/assist/items?limit=1" | jq '.total_count')
        → If total_count > 0: IMMEDIATELY return to Step 1 (no asking)
        → If total_count == 0: Tell user "✅ All items complete!" and stop
```

---

## Prerequisites (assume these are met - do NOT ask)

- Phoenix server running at localhost:4000
- User has `/dev/assist` open in browser
- This project directory is the working directory
- Helper scripts pre-approved: `./scripts/assist-*`

## Helper Scripts

Located in `scripts/`:

| Script | Usage | Description |
|--------|-------|-------------|
| `assist-batch` | `./scripts/assist-batch [limit]` | Start batch of incomplete items |
| `assist-poll` | `./scripts/assist-poll [timeout]` | Poll until user clicks "Start Research" (default: 300s) |
| `assist-skip` | `./scripts/assist-skip <id> '["fields"]'` | Mark fields as skipped (persists to database) |
| `assist-batch-review` | `./scripts/assist-batch-review <id> '<json>'` | Send suggestions for one item (call per item) |
| `assist-batch-review-ready` | `./scripts/assist-batch-review-ready` | Signal all searches done, show review page |
| `assist-batch-review-poll` | `./scripts/assist-batch-review-poll [timeout]` | Poll until user clicks "Save All" (default: 600s) |
| `assist-update` | `./scripts/assist-update <id> '<json>'` | Update item fields |

### Legacy Scripts (single-item review)

| Script | Usage | Description |
|--------|-------|-------------|
| `assist-search` | `./scripts/assist-search <id> '<query>'` | Background Tavily search, writes to `tmp/assist-search-<id>.json` |
| `assist-review` | `./scripts/assist-review <id> '<json>'` | Send single item with suggestions to browser |
| `assist-review-poll` | `./scripts/assist-review-poll [timeout]` | Poll until user clicks "Done" (default: 300s) |

---

## Detailed Workflow

### Step 1: Start a batch

**Run this immediately when user asks to start assist mode. Do NOT ask questions first.**

```bash
./scripts/assist-batch 20
```

This clears any existing batch, fetches up to 20 incomplete items, and sends them to the browser.

Tell user briefly: "Sent X items to browser."

Then immediately run Step 2 (the poll script).

### Step 2: Poll for decisions

**IMPORTANT**: Run this immediately after Step 1. Do NOT wait for user to confirm in chat.

```bash
./scripts/assist-poll 300
```

This script blocks until user clicks "Start Research" in the browser, then returns their decisions. The script detects the button click automatically - no chat confirmation needed:

```json
{
  "status": "ready",
  "batch_id": "abc123",
  "items": [
    {"item_id": 20, "item_name": "M3 Screws", "find": ["manufacturer", "model"], "skip": []},
    {"item_id": 21, "item_name": "Wire Nuts", "find": ["description"], "skip": []}
  ]
}
```

### Step 2b: Skip Persistent Fields

For items where the user unchecked ALL fields (nothing to find):

```bash
./scripts/assist-skip <id> '["manufacturer","model"]'
```

This persists the skip to the database via `item.metadata`. These items won't appear in future batches.

**When to use:** If `item.find` is empty but `item.skip` has values, run assist-skip before moving to Step 3.

**Example:** If the response shows:
```json
{"item_id": 20, "item_name": "Generic M3 Screws", "find": [], "skip": ["model", "description"]}
```

Then run:
```bash
./scripts/assist-skip 20 '["model","description"]'
```

### Step 3: Research All Items

For each item requiring research:

1. **Re-fetch current item data** (user may have added source_url)
   ```bash
   curl -s 'http://localhost:4000/api/assist/items/<id>'
   ```

2. **Search** using Tavily
   - If `source_url` exists: Use `mcp__tavily__tavily_extract` with the URL
   - Otherwise: Use `mcp__tavily__tavily_search` with item name + fields

3. **Send suggestions** for this item:
   ```bash
   ./scripts/assist-batch-review 29 '{"description":"Aliphatic resin wood glue, 30 min clamp time"}'
   ```

**Parallelization**: You can run multiple searches in parallel and send suggestions as each completes. The order doesn't matter.

### Step 4: Show Batch Review Page

After ALL searches are complete and suggestions sent:

```bash
./scripts/assist-batch-review-ready
```

This tells the browser to display all items with their suggestions on a single scrollable page.

### Step 5: Poll for Batch Review

**IMPORTANT**: Run this immediately after Step 4. Do NOT wait for user to confirm in chat.

```bash
./scripts/assist-batch-review-poll 600
```

This script blocks until user clicks "Save All" in the browser. The script detects the button click automatically - no chat confirmation needed. The user can:
- Edit suggested values
- Uncheck fields they don't want to accept
- Review everything at once

Returns:

```json
{
  "status": "ready",
  "batch_id": "abc123",
  "accepted": {
    "29": {"description": "Aliphatic resin wood glue, 30 min clamp time"},
    "30": {"manufacturer": "3M", "model": "B/G Series"},
    "31": {}
  }
}
```

Note: Items with no checked fields have empty objects. Only accepted fields with their (possibly edited) values are included.

### Step 6: Apply Updates

For each item in the accepted result, run the update script:

```bash
./scripts/assist-update 29 '{"description":"Aliphatic resin wood glue, 30 min clamp time"}'
./scripts/assist-update 30 '{"manufacturer":"3M","model":"B/G Series"}'
```

Skip items with empty accepted objects (user unchecked all fields).

**IMPORTANT**: Do NOT show results to user. Do NOT comment on updates. Just run them and immediately proceed to Step 7.

### Step 7: Auto-Loop or Complete

After applying all updates, check for remaining items:

```bash
count=$(curl -s "http://localhost:4000/api/assist/items?limit=1" | jq '.total_count')
```

**If total_count > 0**: Immediately return to Step 1 (start new batch). Do NOT ask for confirmation.

**If total_count == 0**: Tell user "✅ All items complete!" and stop. The browser will return to waiting mode.

**Important**: The user can interrupt at any time if they need a break. Don't ask - just loop.

**Note**: The API returns both `count` (items in response, capped by limit) and `total_count` (all matching items). Use `total_count` to know how many items remain.

---

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/assist/items` | GET | List incomplete items |
| `/api/assist/items/:id` | GET | Get single item details |
| `/api/assist/items/:id` | PATCH | Update item fields |
| `/api/assist/items/:id/skip` | POST | Mark field(s) as skipped |
| `/api/assist/batch/start` | POST | Start batch with item IDs |
| `/api/assist/batch/decisions` | GET | Get user's field selections |
| `/api/assist/batch/clear` | POST | Clear current batch |
| `/api/assist/batch/suggestions` | POST | Add suggestions for an item |
| `/api/assist/batch/review-ready` | POST | Signal all suggestions ready |
| `/api/assist/batch/review-decision` | GET | Get batch review result |

### Legacy Endpoints (single-item review)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/assist/items/:id/review` | POST | Send item with suggestions to browser |
| `/api/assist/review/decision` | GET | Get user's review decision |
| `/api/assist/review/clear` | POST | Clear current review |

### Query Parameters for GET /api/assist/items

- `fields` - Comma-separated fields to check (default: `manufacturer,model,description`)
- `limit` - Maximum items to return (default: 50)

## Notes

- Keep descriptions concise (under 100 characters)
- Use existing item fields to build better search queries
- Skipped fields won't appear in future queries
- The batch UI shows all item details so users can make informed toggle decisions
- The batch review UI allows users to edit suggestions before accepting
- User can walk away during research phase - review when ready
