# Root-relative attachment paths

Status: accepted (storage foundation only)

Related accepted decision: [ADR 0006](../adr/0006-path-aware-attachment-store.md).
The accepted [document and media decision](../adr/0002-separate-documents-and-media.md),
[persistence contract](../arch/persistence.md), and
[interaction model](interaction-model.md) define caller and import behavior.
The accepted [folder-based transfer specification](folder-based-canvas-transfers.md)
adopts parent-aware keys in callers, and that adoption is implemented. This
specification remains limited to the byte-store foundation.

## Scope

This specification lets the byte-only `AttachmentStore` address image files
beneath their canvas folders in the browser's Origin Private File System (OPFS). It
retains each existing UUID-based image filename and keeps document references
relative to their canvas. It changes storage addressing, not image formats or
document schema. Caller and import behavior is defined by the accepted
[folder-based transfer specification](folder-based-canvas-transfers.md); source
callers adopted nested keys after the recorded pre-implementation baseline
`1c4839a`.

Current storage and image validation live in
[`attachment_store.dart`](../../lib/attachments/attachment_store.dart),
[`attachment_store_web.dart`](../../lib/attachments/attachment_store_web.dart),
and [`image_import.dart`](../../lib/attachments/image_import.dart).

The storage key grammar is:

```text
(<safe canvas-directory-segment>/)*attachments/<uuid-v4>.<png|jpg|gif|webp>
```

The prefix may be empty, so existing root keys such as
`attachments/123e4567-e89b-42d3-a456-426614174000.png` remain valid and keep
their current location. `School/attachments/123e4567-e89b-42d3-a456-426614174000.png`
and `Work/attachments/123e4567-e89b-42d3-a456-426614174000.png` are different
keys even though their leaf filenames match. UUID and extension rules remain
the existing lowercase version-4 UUID and `.png`, `.jpg`, `.gif`, or `.webp`
rules.

## Behavior

### Addressing and ownership

`AttachmentStore` remains a byte-storage boundary with the same operations:
`write(String path, Uint8List bytes)`, `read(String path)`,
`readIfExists(String path)`, and `delete(String path)`. It receives a complete
root-relative key. It does not know the active canvas, inspect library or editor
models, infer a containing directory, rewrite document JSON, or translate a key
to another filename. The key is not an operating-system absolute path or a URL.

Saved media continues to use its current canvas-relative reference, for
example `attachments/123e4567-e89b-42d3-a456-426614174000.png`. A root-level
canvas can use that same string as its full storage key. Callers resolve nested
storage keys from explicit canvas-directory context; see
[caller adoption status](#caller-adoption-status).

### Reference recognition and resolution

`isCanvasAttachmentReference(value)` recognizes the existing relative
`attachments/<uuid-v4>.<png|jpg|gif|webp>` reference pattern, separately from
full storage-key validation. `validateAttachmentPath(rootRelativePath)`
validates a complete root-relative storage key against the grammar above.
`resolveAttachmentPath(canvasDirectory, reference)` is a pure operation: it
validates the reference and parent segments, joins them with `/`, then validates
the complete key. An empty parent leaves the reference unchanged; `School` plus
the example reference resolves to
`School/attachments/123e4567-e89b-42d3-a456-426614174000.png`. References from
canvases in the same parent resolve to the same key; different parents resolve
them to different keys. The Workspace/library owner supplies the parent from
the canvas file's path, not global active-canvas state.

Do not broaden relative-reference recognition in a way that changes URI
classification, Markdown discovery, or external media handling. Do not trim,
normalize, or URL-decode stored paths or rewrite external media sources as part
of storage resolution.

Directory spelling is literal, including spaces, Unicode spelling, and case.
OPFS key and library name identity are case-sensitive; exact duplicate sibling
names remain a library-owned rejection policy. Do not create basename fallbacks,
aliases, hashes, generated replacement names, or a persisted filename map.

### Validation and browser storage

Validate the entire key before any storage I/O. Reject empty or absolute paths,
leading or trailing separators, duplicate separators, empty, `.` or `..`
segments, backslashes, control characters including NUL, drive prefixes, and
URL-looking schemes or authorities. The final `attachments` directory and
existing UUID filename and format rules are required. Do not URL-decode: encoded
text is literal, not a traversal instruction. Harmless percent signs in
otherwise valid directory names need not be rejected. Never follow links or
allow traversal outside the OPFS origin root.

The web implementation traverses validated directory segments from
`navigator.storage.getDirectory()` and reaches the `attachments` directory and
file beneath that root. Writes create only the required parent directories.
Reads and deletes do not create directories. This uses OPFS.

Every operation validates the full key before touching OPFS. A malformed key
must fail before root lookup or directory creation. `read` reports a missing
file as an error. `readIfExists` returns `null` only for a genuine missing file;
invalid paths, permissions, corrupt storage, size violations, and other I/O
errors propagate. `delete` is idempotent for a missing file and removes only
the exact leaf. It never recursively deletes directories or tries a basename
fallback. Empty parent directories may remain.

The 10 MiB image limit remains in force and applies at the byte-store boundary
as well as image import validation: reject an oversized write before creating
directories, check file metadata before reading its bytes, and check the actual
read length afterward. Keep image decoding and format validation at the
existing consuming import or upload boundary; the byte store does not add an
image decoder.

A write replaces bytes at exactly the supplied key and succeeds only after the
browser writable closes. On write or close failure, abort the per-file writer
on a best-effort basis and propagate the original failure. Do not report an
empty successful read or successful write after failure. This defines no
store-wide transaction, crash rollback, or concurrent-writer guarantee.

### Caller adoption status

The `AttachmentStore` does not supply canvas context. The pre-implementation
baseline `1c4839a` used root-level keys even when a canvas was nested in the
explorer; parent-aware caller adoption is now implemented under the accepted
folder-based transfer contract. Each caller captures the canvas directory and
resolves a full key before asynchronous work, then uses that same key for reads,
writes, and cleanup. Navigation must not let a delayed operation retarget a
different folder. Retained image caches and asynchronous resource identity
include the resolved key or its captured canvas context, not only the relative
source string.

| Caller area | Parent-aware handling |
| --- | --- |
| Media and Markdown rendering ([`media_resources.dart`](../../lib/canvas/editor/elements/media/media_resources.dart), [`text_markdown_images.dart`](../../lib/canvas/editor/elements/text/text_markdown_images.dart)) | Resolve the saved relative source using the owning canvas directory; key retained reads by the resolved storage identity. |
| Upload and clipboard edits ([`canvas_clipboard.dart`](../../lib/canvas/editor/canvas_clipboard.dart), [`text_markdown_editor.dart`](../../lib/canvas/editor/elements/text/text_markdown_editor.dart)) | Resolve the target's captured canvas directory once; write and clean up only that full, unpublished key. |
| Transfer codec ([`canvas_transfer.dart`](../../lib/library/transfer/canvas_transfer.dart), [`canvas_transfer_zip.dart`](../../lib/library/transfer/canvas_transfer_zip.dart), [`attachment_references.dart`](../../lib/canvas/document/attachment_references.dart)) | Resolve each reference against its document path before reading bytes; preserve the portable reference separately. |
| Library import and upload staging ([`library_controller.dart`](../../lib/library/library_controller.dart)) | `LibraryController` owns publication. Transfer import writes to exact full keys under its accepted best-effort policy; uploads and pending editor operations retain cleanup limited to their own new unpublished keys. |
| All callers | Capture explicit canvas-directory context and resolve full keys, including for nested explorer folders; the store does not infer keys from explorer paths. |

Full-path keys distinguish files in different canvas folders, but do not by
themselves make replacement of already-published bytes at the same key safe.
The accepted folder-based transfer contract defines same-key import writes and
their best-effort failure behavior. This storage specification does not define
that multi-file import policy or make import atomic.

### Caller acceptance criterion

- Cleanup uses the originally captured full key and cannot delete or retarget a
  file in another canvas directory.

## Acceptance criteria

- The same leaf filename under two canvas directories reads, writes, and deletes
  independently; a root-level existing key still reads at its original path.
- Storage round-trips bytes at the exact supplied filename without renaming,
  flattening, or persisting a mapping.
- `resolveAttachmentPath(canvasDirectory, reference)` returns the root key for
  an empty parent, the nested key for a nested parent, the same key for
  references from canvases in one parent, and different keys for the same
  reference in different parents.
- All four store operations reject each invalid path before any OPFS lookup or
  mutation. A write creates only required parents; read and delete create none.
- `read` rejects a missing file; `readIfExists` returns `null` only for a
  missing file and propagates other failures. Delete removes only its exact
  file and tolerates its absence.
- Oversized writes fail before directory creation. Reads check declared size
  before buffering and actual size afterward. A failed write propagates its
  error and is not reported as success.

## Non-goals

This specification does not change image formats or filenames, document schema,
portable relative references, or define import publication, library
case-conflict rules, canvas-move semantics, cross-folder clipboard semantics,
remote transfer behavior, or external media sources. It does not
introduce transactions, versioning, journals, pointer indirection, sync,
filename mappings, or a generic storage-provider framework.
