# Inventory Assist Instructions

Instructions for Claude Code to assist with completing missing inventory item details.

## Quick Reference - Execute In Order

**IMPORTANT: Follow these steps exactly.**
**This is an outline of the process. You can find more detailed instructions in the Detailed Workflow section below.**

```
STEP 1: ./scripts/assist-batch 20
        → Tell user: "Toggle fields, add product URLs if you have them, click Start Research"

STEP 2: ./scripts/assist-poll 300
        → BLOCKS until user clicks "Start Research"
        → Returns JSON with items and which fields to find/skip

STEP 2b: For items with ONLY skip fields (nothing to find):
         ./scripts/assist-skip <id> '["field1","field2"]'
         → Persists skip to database, item won't appear in future batches

STEP 3: For FIRST item needing research:
        a) curl -s 'http://localhost:4000/api/assist/items/<id>'
           → Check if source_url is populated
        b) IF source_url exists:
              Use mcp__tavily__tavily_extract with the URL
           ELSE:
              Use mcp__tavily__tavily_search (synchronous)
        c) ./scripts/assist-review <id> '{"field":"value"}'
        d) Launch background searches for remaining items:
           ./scripts/assist-search <id> "query" (run_in_background=true)

STEP 4: ./scripts/assist-review-poll 300
        → BLOCKS until user clicks "Done"
        → Returns accepted values (may be edited by user)

STEP 5: ./scripts/assist-update <id> '<accepted_json>'
        → Apply the ACCEPTED values from step 4

STEP 6: Repeat steps 3c-5 for remaining items:
        - Read tmp/assist-search-<id>.json for search results
        - Send to browser with assist-review
        - Poll with assist-review-poll
        - Apply with assist-update

STEP 7: curl -s "http://localhost:4000/api/assist/items?limit=1" | jq '.count'
        → If count > 0, ask user if they want another batch
```

---

## Prerequisites

- Phoenix server running (`mix phx.server`)
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
| `assist-search` | `./scripts/assist-search <id> '<query>'` | Background Tavily search, writes to `tmp/assist-search-<id>.json` |
| `assist-review` | `./scripts/assist-review <id> '<json>'` | Send item with suggestions to browser |
| `assist-review-poll` | `./scripts/assist-review-poll [timeout]` | Poll until user clicks "Done" (default: 300s) |
| `assist-update` | `./scripts/assist-update <id> '<json>'` | Update item fields |

---

## Detailed Workflow

### Step 1: Start a batch

```bash
./scripts/assist-batch 20
```

This clears any existing batch, fetches incomplete items, and sends them to the browser. Returns JSON with item details.

Tell user: "I've sent X items to your browser. Toggle which fields you want me to research. If you have a product URL (manufacturer page, Amazon, etc.), paste it in for direct lookup. Then click **Start Research**."

### Step 2: Poll for decisions

```bash
./scripts/assist-poll 300
```

This blocks until user clicks "Start Research", then returns their decisions:

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

### Step 3: Pipelined Research and Review

This step pipelines search and review operations so the user can start reviewing immediately while remaining searches run in background.

**Important:** Re-fetch fresh item data before searching. The user may have updated items after the batch was created:

```bash
curl -s 'http://localhost:4000/api/assist/items/<id>'
```

#### Pipeline Execution Flow

```
[Search 1] → [Review 1] ← user working
   [Search 2, 3, 4 in background]
             [Review 2] ← user working
             [Review 3] ← user working
             [Review 4] ← user working
```

#### 3a. First Item (Synchronous)

For the first item requiring research:

1. **Re-fetch current item data**
2. Build search query using item's name + existing fields
3. Use `mcp__tavily__tavily_search` with `search_depth: "advanced"` (synchronous)
4. Extract requested fields and send to browser immediately:

```bash
./scripts/assist-review 29 '{"description":"Aliphatic resin wood glue, 30 min clamp time"}'
```

#### 3b. Launch Background Searches

For remaining items (2..N), launch searches in background using Bash `run_in_background`:

```bash
./scripts/assist-search 30 "3M wire nuts specifications AWG range"
./scripts/assist-search 31 "Titebond wood glue dry time specifications"
```

Each writes results to `tmp/assist-search-<item_id>.json`.

#### 3c. Poll for First Review

Start polling for user's review decision (run in background):

```bash
./scripts/assist-review-poll 300
```

#### 3d. Process Pipeline

Alternate between checking completed operations:

1. **Check review poll** - If user clicked "Done":
   - Apply accepted values: `./scripts/assist-update <id> '<json>'`
   - Send next completed search result to browser
   - Restart review poll

2. **Check background searches** - Read completed search results:
   - Parse `tmp/assist-search-<id>.json`
   - Extract requested fields
   - Queue for review (or send immediately if review slot available)

3. **Repeat** until all items processed

#### Example Pipeline for 3 Items

```
1. Item 29 (Wood Glue): tavily_search → send to browser → poll review
2. Item 30 (Wire Nuts): ./scripts/assist-search 30 "..." (background)
3. Item 31 (Screws): ./scripts/assist-search 31 "..." (background)
4. User finishes Item 29 → apply update → read tmp/assist-search-30.json → send Item 30 to browser
5. User finishes Item 30 → apply update → read tmp/assist-search-31.json → send Item 31 to browser
6. User finishes Item 31 → apply update → done
```

#### Review UI

The browser shows:
- Current item details (name, location, manufacturer, model, description)
- Suggested values in editable text boxes
- Checkboxes to accept/reject each suggestion (default: checked)
- "Done" button

Review poll returns:

```json
{
  "status": "ready",
  "item_id": 29,
  "accepted": {
    "description": "Aliphatic resin wood glue, 30 min clamp time"
  }
}
```

The `accepted` object contains only the fields the user checked, with their (possibly edited) values.

### Step 4: Continue or finish

After processing all items, check for remaining incomplete items:

```bash
curl -s "http://localhost:4000/api/assist/items?limit=1" | jq '.count'
```

If count > 0, ask user if they want another batch. Otherwise, workflow complete.

---

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/assist/items` | GET | List incomplete items |
| `/api/assist/items/:id` | GET | Get single item details |
| `/api/assist/items/:id` | PATCH | Update item fields |
| `/api/assist/items/:id/skip` | POST | Mark field(s) as skipped |
| `/api/assist/items/:id/review` | POST | Send item with suggestions to browser |
| `/api/assist/batch/start` | POST | Start batch with item IDs |
| `/api/assist/batch/decisions` | GET | Get user's field selections |
| `/api/assist/batch/clear` | POST | Clear current batch |
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
- The review UI allows users to edit suggestions before accepting
