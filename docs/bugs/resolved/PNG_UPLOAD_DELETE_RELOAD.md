# Bug: Page Reload on PNG Upload/Delete

**Status: RESOLVED**
**Date Resolved: 2026-01-23**

## Summary
Uploading or deleting PNG/JPEG images in the item modal's Documents section caused a full page reload. PDF documents worked correctly.

## Root Cause
The `phoenix_live_reload` configuration in `config/dev.exs` was watching for changes to image files in `priv/static/`:

```elixir
~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E
```

This pattern excluded `uploads/` but NOT `documents/`. When a PNG/JPEG document was deleted from `priv/static/documents/`, the live_reload watcher detected the file system change and triggered a full page reload.

PDFs worked correctly because `.pdf` was not in the watched extensions list.

## Solution
Updated the live_reload pattern to also exclude the `documents/` directory:

```elixir
~r"priv/static/(?!uploads/|documents/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E
```

**File changed:** `config/dev.exs`

## Symptoms (for reference)
- Uploading a PNG file from computer triggered page reload
- Deleting a PNG document triggered page reload
- PDF documents worked correctly
- No JavaScript errors visible in console
- No server-side errors - handlers completed successfully
- Stack trace pointed to `phoenix/live_reload/frame` as the source of navigation

## Key Debugging Insight
Adding a `beforeunload` event listener with `console.trace()` revealed the stack trace originated from `phoenix_live_reload`, not from LiveView or application code.

## Date Identified
2026-01-23
