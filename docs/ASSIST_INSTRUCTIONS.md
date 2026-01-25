# Inventory Assist Instructions

Instructions for Claude Code to assist with completing missing inventory item details.

## Prerequisites

- Phoenix server running (`mix phx.server`)
- User has `/dev/assist` open in browser
- This project directory is the working directory

## Workflow

### Step 1: Verify server is running

```bash
curl -s http://localhost:4000/api/assist/items?fields=manufacturer,model | head -c 100
```

If this fails, server is not running.

### Step 2: Get incomplete items

```bash
curl -s "http://localhost:4000/api/assist/items?fields=manufacturer,model,description"
```

Response format:
```json
{
  "items": [
    {
      "id": 1,
      "name": "Blue screwdriver",
      "manufacturer": null,
      "model": null,
      "description": null,
      "photo_path": "items/abc123.jpg",
      "location_code": "A-1",
      "missing_fields": ["manufacturer", "model", "description"]
    }
  ],
  "count": 42
}
```

Show the user a summary: "Found X items with missing information."

### Step 3: For each item, loop through this process:

#### 3a. Display in browser

```bash
curl -X POST "http://localhost:4000/api/assist/items/42/show"
```

Tell user: "Displaying [item name] in browser. Check the photo."

#### 3b. Build search query

Construct a web search query from:
- Item name (required)
- Manufacturer (if present)
- Model (if present)
- Any identifying info visible in description

Example: "Bosch circular saw GKS 190 specifications"

#### 3c. Search the web

Use WebSearch tool to find:
- Manufacturer's product page
- Retailer listings (Amazon, Home Depot, etc.)
- Specification sheets

#### 3d. Extract and present information

From search results, extract:
- **Manufacturer**: The brand/company name
- **Model**: Model number, part number, or SKU
- **Description**: Brief description of what the item is

Present to user:
```
Based on my search, I found:
- Manufacturer: Bosch
- Model: GKS 190
- Description: 7-1/4" circular saw, 15 amp

Options:
1. Accept all
2. Modify (tell me what to change)
3. Skip this item
4. Skip specific field(s)
```

#### 3e. Apply user's choice

**If accept/modify:**
```bash
curl -X PATCH "http://localhost:4000/api/assist/items/42" \
  -H "Content-Type: application/json" \
  -d '{"manufacturer": "Bosch", "model": "GKS 190", "description": "7-1/4\" circular saw, 15 amp"}'
```

**If skip entire item:**
```bash
curl -X POST "http://localhost:4000/api/assist/items/42/skip" \
  -H "Content-Type: application/json" \
  -d '{"fields": ["manufacturer", "model", "description"]}'
```

**If skip specific field:**
```bash
curl -X POST "http://localhost:4000/api/assist/items/42/skip" \
  -H "Content-Type: application/json" \
  -d '{"fields": ["model"]}'
```

### Step 4: Continue to next item

Repeat Step 3 for remaining items.

### Step 5: Complete

When no items remain, tell user: "All incomplete items have been processed!"

## User Commands During Workflow

- "skip" or "skip this item" → Skip all missing fields for current item
- "skip [field]" → Skip just that field (e.g., "skip model")
- "accept" → Accept all suggested values
- "change [field] to [value]" → Modify a specific field
- "stop" or "done" → End the workflow early

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/assist/items` | GET | List incomplete items |
| `/api/assist/items/:id` | GET | Get single item details |
| `/api/assist/items/:id/show` | POST | Display item in browser |
| `/api/assist/items/:id` | PATCH | Update item fields |
| `/api/assist/items/:id/skip` | POST | Skip field(s) |

### Query Parameters for GET /api/assist/items

- `fields` - Comma-separated list of fields to check (default: `manufacturer,model,description`)
- `limit` - Maximum items to return (default: 50)
- `inventory_id` - Override current inventory (optional)

## Notes

- Always show the item in browser before searching
- Wait for user confirmation before making any changes
- If search yields no results, offer to skip or let user provide manual input
- Keep descriptions concise (under 100 characters ideally)
- Skipped fields won't appear in future queries
