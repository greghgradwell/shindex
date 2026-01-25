# Inventory Assist Instructions

Instructions for Claude Code to assist with completing missing inventory item details.

## Prerequisites

- Phoenix server running (`mix phx.server`)
- User has `/dev/assist` open in browser
- This project directory is the working directory
- Helper scripts pre-approved: `./scripts/assist-*`

## Helper Scripts

Located in `scripts/`:

| Script | Usage | Description |
|--------|-------|-------------|
| `assist-batch` | `./scripts/assist-batch [limit]` | Start batch of incomplete items (default: 5) |
| `assist-poll` | `./scripts/assist-poll [timeout]` | Poll until user clicks "Start Research" (default: 300s) |
| `assist-show` | `./scripts/assist-show <id>` | Display item in browser for review |
| `assist-update` | `./scripts/assist-update <id> '<json>'` | Update item fields |

## Batch Workflow

### Step 1: Start a batch

```bash
./scripts/assist-batch 5
```

This clears any existing batch, fetches incomplete items, and sends them to the browser. Returns JSON with item details.

Tell user: "I've sent X items to your browser. Toggle which fields you want me to research, then click **Start Research**."

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

### Step 3: Parallel research

For each item with `find` fields, spawn parallel Task agents:

```
Task 1: Search for "M3 Screws stainless steel" → manufacturer, model
Task 2: Search for "3M T/R+ wire nuts" → description
Task 3: Search for "Titebond Original wood glue" → description
```

Use the item's existing fields (name, manufacturer, model) to build search queries.

### Step 4: Review results one-by-one

For each item:

#### 4a. Display in browser

```bash
./scripts/assist-show 20
```

#### 4b. Present findings

```
**Wire Nuts** (Item 2 of 3)

| Field | Current | Suggested |
|-------|---------|-----------|
| Manufacturer | 3M | — |
| Model | T/R+ | — |
| Description | *Missing* | **Twist-on wire connectors for 22-8 AWG copper** |

Options:
1. **Accept** — apply this description
2. **Modify** — tell me what to change
3. **Skip** — leave empty
```

#### 4c. Apply user's choice

**If accept (user says "1" or "accept"):**
```bash
./scripts/assist-update 21 '{"description":"Twist-on wire connectors for 22-8 AWG copper"}'
```

**If skip (user says "3" or "skip"):**
Move to next item without updating.

**If modify (user says "2" or provides new value):**
Apply the modified value using `assist-update`.

### Step 5: Continue or finish

After processing all items, check for remaining incomplete items:

```bash
curl -s "http://localhost:4000/api/assist/items?limit=1" | jq '.count'
```

If count > 0, ask user if they want another batch. Otherwise, workflow complete.

---

## User Commands During Review

- `1` or `accept` → Apply suggested values
- `2` or `modify` → User will provide corrections
- `3` or `skip` → Leave fields empty, move to next item
- `stop` or `done` → End workflow early

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/assist/items` | GET | List incomplete items |
| `/api/assist/items/:id` | GET | Get single item details |
| `/api/assist/items/:id/show` | POST | Display item in browser |
| `/api/assist/items/:id` | PATCH | Update item fields |
| `/api/assist/items/:id/skip` | POST | Mark field(s) as skipped |
| `/api/assist/batch/start` | POST | Start batch with item IDs |
| `/api/assist/batch/decisions` | GET | Get user's field selections |
| `/api/assist/batch/clear` | POST | Clear current batch |

### Query Parameters for GET /api/assist/items

- `fields` - Comma-separated fields to check (default: `manufacturer,model,description`)
- `limit` - Maximum items to return (default: 50)

## Notes

- Keep descriptions concise (under 100 characters)
- Use existing item fields to build better search queries
- Skipped fields won't appear in future queries
- The batch UI shows all item details so users can make informed toggle decisions
