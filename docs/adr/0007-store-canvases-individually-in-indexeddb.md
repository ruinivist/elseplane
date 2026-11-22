# Store canvases individually in IndexedDB

Status: accepted and implemented

Date: 2026-11-21

## Context

The former browser library store serialized the entire library into one
`localStorage` entry. Editing one canvas rewrote all canvas documents, and
the whole library shared the browser's small
[`localStorage` quota](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria#web_storage).
Pen strokes add to that load, but a smaller stroke encoding would not stop
saves from rewriting unrelated canvases.

## Decision

- Store each canvas document in its own IndexedDB record, keyed by its stable
  canvas ID rather than its file path. Store library metadata separately from
  document content. A canvas-only autosave writes only the changed canvas
  records and does not serialize or write unrelated canvas documents.
- Keep the single library persistence queue and revision checks. When a library
  operation changes both metadata and documents, commit its IndexedDB changes
  in one transaction before publishing the result. A failed save must leave
  pending edits available for retry.
- Keep versioned canvas JSON, including the current pen point representation.
  Keep image bytes in the Origin Private File System (OPFS). This decision does
  not change attachment paths or local and GitHub transfer formats.

## Alternatives

- Split canvas documents across `localStorage` keys. This avoids some rewrites
  but keeps the shared quota and offers no transaction across keys.
- Store canvas JSON in OPFS alongside attachments. This allows per-canvas
  writes but would require the app to coordinate changes across files that
  IndexedDB can commit in one transaction.

## Consequences

This is a clean cutover. The app does not read, migrate, or delete old
`localStorage` library data. Existing development libraries in that store will
not appear after the switch. Unreadable IndexedDB data is a load error, not an
empty library.

IndexedDB transactions cover library records, not image files in OPFS. The
existing [transfer failure rules](../arch/persistence.md#folder-based-transfers)
still apply. Browser storage remains subject to quota and site-data removal.
