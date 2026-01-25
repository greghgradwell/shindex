# Bug: Flash Messages Not Displaying After LiveView Actions

## Status: RESOLVED

## Summary

Flash messages set via `put_flash/3` in LiveView event handlers never appear to the user. Messages only display on initial page load, not after subsequent actions.

## Root Cause

The `flash_group` component was rendered in `root.html.heex` (the static root layout), which is outside LiveView's DOM patching area. LiveView can only update content inside `{@inner_content}`.

```
root.html.heex (BEFORE - broken):
┌─────────────────────────────────────┐
│ <body>                              │
│   <nav>...</nav>                    │
│   <main>                            │
│     <flash_group />  ← STATIC       │  ← Never re-renders
│     {@inner_content} ← LIVE         │  ← LiveView patches here
│   </main>                           │
│ </body>                             │
└─────────────────────────────────────┘
```

When `put_flash/3` is called:
1. Flash state updates in the socket
2. The flash container in root layout is never re-rendered
3. User sees nothing

## Affected Areas

All LiveView flash messages throughout the application:
- Item save/update confirmations
- Quantity update confirmations
- Archive/restore confirmations
- Document upload confirmations
- Location move confirmations
- Error messages
- Any other `put_flash/3` calls

## Solution

Implemented the standard Phoenix layout pattern:

1. Created `app.html.heex` as a **live layout** containing the `flash_group`
2. Removed `flash_group` from `root.html.heex`
3. Configured `live_session` in router to use the live layout

```
AFTER (fixed):
┌─────────────────────────────────────┐
│ root.html.heex (static)             │
│   {@inner_content} ─────────────────┼──┐
└─────────────────────────────────────┘  │
                                         ▼
┌─────────────────────────────────────┐
│ app.html.heex (live layout)         │
│   <flash_group />  ← LIVE           │  ← Re-renders with LiveView
│   {@inner_content} ← LIVE           │
└─────────────────────────────────────┘
```

## Files Changed

- `lib/inventory_locator_web/components/layouts/app.html.heex` (created)
- `lib/inventory_locator_web/components/layouts/root.html.heex` (removed flash_group)
- `lib/inventory_locator_web/router.ex` (added layout to live_session)

## Testing

1. Edit any item and click Save - should see "Item saved" toast
2. Increment/decrement quantity - should see "Quantity updated" toast
3. Archive an item - should see confirmation toast
4. Upload a document - should see "Document uploaded" toast

## References

- Phoenix LiveView Layouts: https://hexdocs.pm/phoenix_live_view/live-layouts.html
