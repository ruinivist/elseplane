# Browser canvas persistence

Status: accepted

## Scope

This specification covers local browser saves. [ADR 0007](../adr/0007-store-canvases-individually-in-indexeddb.md) records the storage decision. The [interaction model](interaction-model.md) and [transfer specification](folder-based-canvas-transfers.md) still govern editing, file switching, and transfers.

## Behavior

- Autosave writes only the canvas documents with completed edits to save. Editing one canvas does not serialize or rewrite any other canvas document. File selection, renaming, moving, and changes to GitHub tracking do not rewrite unchanged documents.
- Keep completed edits available for retry after a failed save. A late save must not mark a newer edit saved. Save completed edits before switching canvases; if the save fails, keep the current canvas open.
- Library changes that add, replace, or remove documents publish together with their library metadata after the local save succeeds. A failed save does not publish a partial library change. This guarantee does not cover attachment files: the existing attachment and transfer failure rules still apply.
- On reload, restore canvas IDs and contents, folder hierarchy and order, the last-opened canvas, and saved GitHub tracking. Start a new library if IndexedDB has no saved library. Do not read or migrate the former `localStorage` library.
- Show the existing load failure if the IndexedDB library cannot be read. Do not open or save a blank replacement.
- Portable canvas JSON, pen samples, attachment references, exports, and GitHub transfers stay unchanged. Browser storage is not a backup; clearing site data can remove both documents and images. Live editing of the same library in multiple tabs is not supported.

## Acceptance criteria

- Create two canvases, edit one, and reload. The edit is restored and the other canvas document was not serialized or written during autosave.
- Rename or move a canvas, then reopen it. Its contents and ID are unchanged; image references still resolve according to the current move rules.
- Interrupt a save and verify edits remain available for retry. Load an unreadable IndexedDB library and verify the app reports an error without opening a blank replacement.
