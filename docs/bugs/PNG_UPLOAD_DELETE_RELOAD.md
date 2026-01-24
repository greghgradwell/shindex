# Bug: Page Reload on PNG Upload/Delete

## Summary
Uploading or deleting PNG images in the item modal's Documents section causes a full page reload. PDF documents work correctly.

## Symptoms
- Uploading a PNG file from computer triggers page reload
- Deleting a PNG document triggers page reload
- Fetching documents via URL works (tested with PDF)
- Uploading/deleting PDF documents works correctly
- No JavaScript errors visible in console (console clears on reload)
- No server-side errors - handlers complete successfully

## Verified Behavior
Server logs show the delete handler completes fully before reload:
```
DELETE_DOCUMENT: Starting
DELETE_DOCUMENT: Got document_id 8
DELETE_DOCUMENT: Got document Screenshot from 2026-01-23 14-08-09.png
DELETE_DOCUMENT: Deleted successfully
DELETE_DOCUMENT: Refreshed list, 0 documents
[info] GET /
[info] Sent 200 in 22ms
[info] CONNECTED TO Phoenix.LiveView.Socket
```

The `{:noreply, socket}` is returned successfully, then the browser navigates to `/`.

## What We Ruled Out
1. **Nested forms** - Moved PhotoCapture outside main form, added `phx-submit` to document upload form
2. **`data-confirm` attribute** - Removed and replaced with `JS.push`
3. **Server-side crashes** - All handlers complete without error
4. **Form submission** - Delete button has `type="button"` and uses `JS.push`

## Affected Files
- `lib/inventory_locator_web/live/item_live/show_modal.ex` - Document event handlers
- `lib/inventory_locator_web/live/item_live/show_modal.html.heex` - Document upload UI
- `lib/inventory_locator/media.ex` - Document storage functions

## Technical Context
- LiveView upload with `auto_upload: true`
- Accepted types: `.pdf`, `.png`, `.jpg`, `.jpeg`
- ShowModal is a LiveComponent rendered in ItemLive.Index
- Upload form uses `phx-change="document_changed"` and `phx-submit="document_changed"`

## Theories to Investigate
1. **LiveView image handling** - LiveView has special handling for images (e.g., `live_img_preview`). Something in the JS might be triggered for image MIME types.
2. **phoenix_html interference** - The `phoenix_html` import handles `data-method` and `data-confirm`. Could be interfering with image-related actions.
3. **Browser behavior** - The browser might be doing something special when it detects image content types in the response.
4. **LiveView diff/patch failure** - The DOM patch after updating the documents list might be failing silently for images, causing a full reload fallback.

## How to Reproduce
1. Go to any item's detail modal (click an item from the list)
2. Scroll to Documents section
3. Click "Select File" and choose a PNG image
4. Observe page reload after upload completes
5. Alternatively: Upload a PNG via URL, then click delete - page reloads

## Workaround
Currently none. URL-based document fetch works for PDFs.

## Related Issues
- Flash messages don't display for LiveView events (separate issue - flash_group is in root layout which doesn't re-render on LiveView socket updates)
- Silent failures throughout the codebase need better error handling

## Date Identified
2026-01-23
