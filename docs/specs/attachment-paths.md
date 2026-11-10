# Root-relative attachment paths

Status: proposed

Related proposal: [ADR 0006](../adr/0006-path-aware-attachment-store.md). The
accepted [document and media decision](../adr/0002-separate-documents-and-media.md),
[persistence contract](../arch/persistence.md), and
[interaction model](interaction-model.md) remain authoritative until proposals
that affect them are accepted and aligned.

## Scope

This proposal lets the byte-only `AttachmentStore` address image files beneath
their canvas folders in the browser's Origin Private File System (OPFS). It
retains each existing UUID-based image filename and keeps document references
relative to their canvas. It changes storage addressing, not image formats,
document schema, or import transactions.

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
example `attachments/123e4567-e89b-42d3-a456-426614174000.png`. The owner that
knows the canvas file's parent supplies that directory explicitly when
resolving reads, writes, and cleanup targets. A pure resolver can be expressed
as `resolveAttachmentPath(canvasDirectory, reference)`: an empty directory
leaves the reference unchanged; `School` plus that reference yields
`School/attachments/123e4567-e89b-42d3-a456-426614174000.png`. Two canvases in
the same parent resolve a shared relative reference to the same key; canvases
in different parents resolve it to separate keys. The Workspace/library owner
supplies the containing directory explicitly; it comes from the canvas file's
parent, not global active-canvas state. The resolver validates the relative
reference and parent segments, joins them with `/`, and validates the complete
key before returning it.

Keep document-reference recognition distinct from full storage-key validation.
The existing `attachmentPathPattern` currently serves both jobs in some
callers. Proposed pure operations in `attachment_store.dart` are
`isCanvasAttachmentReference(value)` for the existing relative-reference
pattern, `validateAttachmentPath(rootRelativePath)` for the full storage-key
grammar, and `resolveAttachmentPath(canvasDirectory, reference)` for explicit
composition. These names are illustrative. Do not broaden relative-reference
recognition in a way that changes URI classification, Markdown discovery, or
external media handling. Do not trim, normalize, or URL-decode stored paths or
rewrite external media sources as part of storage resolution.

Directory spelling is literal, including spaces, Unicode spelling, and case.
OPFS key identity is case-sensitive; case-folding and sibling-name conflicts
remain library-owned policies. Do not create basename fallbacks, aliases,
hashes, generated replacement names, or a persisted filename map.

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
Reads and deletes do not create directories. This uses OPFS; it does not add a
public filesystem picker or the folder-transfer adapter proposed separately.

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

### Callers and import safety

The `AttachmentStore` does not supply canvas context. The owning layer must
capture the canvas directory and resolve a full key before asynchronous work,
then use that same key for its read, write, and cleanup. Navigation must not let
a delayed operation retarget a different folder. Retained image caches and
asynchronous resource identity must include the resolved key or its captured
canvas context, not only the relative source string.

| Caller area | Required context handling |
| --- | --- |
| Media and Markdown rendering ([`media_resources.dart`](../../lib/canvas/editor/elements/media/media_resources.dart), [`text_markdown_images.dart`](../../lib/canvas/editor/elements/text/text_markdown_images.dart)) | Resolve the saved relative source using the owning canvas directory; key retained reads by the resolved storage identity. |
| Upload and clipboard edits ([`canvas_clipboard.dart`](../../lib/canvas/editor/canvas_clipboard.dart), [`text_markdown_editor.dart`](../../lib/canvas/editor/elements/text/text_markdown_editor.dart)) | Resolve the target's captured canvas directory once; write and clean up only that full, unpublished key. |
| Project and snapshot discovery ([`canvas_project.dart`](../../lib/library/transfer/canvas_project.dart)) | Resolve each reference against its document path before reading bytes; preserve the portable reference separately. |
| Library import and [`_stage`](../../lib/library/library_controller.dart) | Keep staging and publication in the library owner. Do not write over a published key as preparation; retain cleanup limited to new unpublished keys and existing async lifetime guards. |
| Existing flat callers | All existing canvases keep their current root keys until a higher layer explicitly adopts directory context. The store must not infer a new key from their explorer paths. |

Full-path keys distinguish files in different canvas folders, but do not by
themselves make replacement of already-published bytes at the same key safe.
The folder-snapshot proposal's overwrite and failure-safety behavior therefore
needs a separate integration decision before adopting nested keys; this
proposal does not replace current fresh-path staging or make multi-file import
atomic.

## Acceptance criteria

- The same leaf filename under two canvas directories reads, writes, and deletes
  independently; a root-level existing key still reads at its original path.
- Storage round-trips bytes at the exact supplied filename without renaming,
  flattening, or persisting a mapping.
- The pure resolver returns the root key for an empty parent, the nested key for
  a nested parent, the same key for references from canvases in one parent, and
  different keys for the same reference in different parents.
- All four store operations reject each invalid path before any OPFS lookup or
  mutation. A write creates only required parents; read and delete create none.
- `read` rejects a missing file; `readIfExists` returns `null` only for a
  missing file and propagates other failures. Delete removes only its exact
  file and tolerates its absence.
- Oversized writes fail before directory creation. Reads check declared size
  before buffering and actual size afterward. A failed write propagates its
  error and is not reported as success.
- Caller cleanup uses its originally captured full key and cannot delete or
  retarget a file in another canvas directory.

## Non-goals

This proposal does not change image formats or filenames, document schema,
portable relative references, import/restore staging, publication atomicity,
library case-conflict rules, canvas-move semantics, cross-folder clipboard
semantics, remote transfer behavior, or external media sources. It does not
introduce transactions, versioning, journals, pointer indirection, sync,
filename mappings, or a generic storage-provider framework.
