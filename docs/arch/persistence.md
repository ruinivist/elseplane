# Persistence

## Library ownership

`LibraryController` owns the immutable published library, pending document
revisions, and one persistence queue. `LibraryStore` reads and writes snapshots
without a second mutable library. Workspace passes editor snapshots to the
library and flushes the outgoing file before replacing its editor. Structural
library operations use the same queue.

## Attachment storage

`AttachmentStore` owns bytes only. It validates complete root-relative keys and
does not inspect canvas, library, or editor state or rewrite document
references. The web implementation stores files under the browser's OPFS origin
root. The 10 MiB limit applies to writes before directory creation and to reads
before buffering, with a second check of the actual read length. `read` fails
for a missing file; `readIfExists` returns `null` only for genuine absence.
Deletes affect only the exact file and tolerate absence. A write succeeds only
after its writer closes; failures propagate after a best-effort abort. See the
accepted [attachment path specification](../specs/attachment-paths.md) for path
validation and operation details.

Canvas-relative references remain unchanged. Owners derive a full storage key
from the canvas parent and relative reference, capture it before asynchronous
work, and use that key consistently for reads, writes, cleanup, and resource
identity. Root-level keys remain valid for root canvases. The accepted
[transfer specification](../specs/folder-based-canvas-transfers.md) defines
caller behavior and import publication; remaining integration and verification
are tracked in the [active plan](../plans/folder-based-canvas-transfers.md).

## Saving

- Every queued write captures file identity, revision, and snapshot. Failed
  writes retain unsaved state; a late write cannot mark newer content saved.
- Failed loading must not silently overwrite unreadable saved data with an
  empty document.
- Workspace owns the open editor session and forwards document-change
  notifications to the library. File switching flushes completed edits before
  replacement without waiting for pending clipboard or upload work; failed
  flushes preserve the open editor for retry. Pending work has no persistence
  guarantee.

## Folder-based transfers

The accepted [transfer specification](../specs/folder-based-canvas-transfers.md)
and [ADR 0005](../adr/0005-folder-based-canvas-transfers.md) define local and
GitHub transfer formats, validation, and failure behavior. Portable trees contain
direct versioned `CanvasDocument` JSON and referenced image bytes at
canvas-parent-relative paths; document references stay relative and media bytes
remain separate. ZIP is a container, not a document format. Base64 JSON canvas
transfers remain unsupported. Remote media persists only its source URL and
geometry; provider metadata and thumbnails remain runtime-only. See the accepted
[media link cards decision](../adr/0003-media-link-cards-without-embeds.md).

`LibraryController` owns additive import publication through the existing queue.
After complete validation and one collision confirmation outside the queue, it
writes referenced available images to exact full keys, stops on the first image
write failure, and saves merged metadata once only after all image writes
succeed. Failure can leave image bytes changed while the previously published
library remains unchanged; no rollback or multi-file atomicity is promised.
Local extras and current selection remain. Import and export sizes, ZIP
integrity, path validation, skips, and UI behavior are specified in the accepted
transfer specification.

The library snapshot stores only the selected GitHub destination, not the
installation ID, discovery results, access tokens, per-canvas remote baseline,
attachment-name map, or pending-write guard. Installation/repository discovery
and the installation ID used for a transfer remain in memory; after reload the
feature resolves the saved account/repository against current authorized
discovery. Only explicit repository setup/change saves the destination. Import
and Commit use it without changing persistence. Repository import reads the
latest default-branch tree and uses the same additive local merge; a current-canvas
checkpoint independently captures a fresh head and publishes one commit while
preserving unrelated paths. An uncertain remote update is reported without
automatic retry. Portable transfers contain no GitHub destination or
credentials.

Media source strings are raw user content, not a transfer validation boundary.
Clipboard, project, and library decoding preserve them without URL
normalization or source rejection. At runtime, the editor resolves a trimmed
copy for loading or opening, defaulting bare addresses and protocol-relative
addresses to HTTPS; unsupported or unusable sources remain unresolved and are
never requested or opened. Canvas-relative attachment-reference discovery and
upload image validation remain unchanged; transfer archive validation and
publication follow the accepted transfer specification.
Storage-key validation follows the accepted
[attachment path specification](../specs/attachment-paths.md).

Preserve path, byte-size, archive-entry, image-upload, and
attachment-reference validation. Import may overwrite referenced bytes at an
exact shared key as specified by ADR 0005; move and clipboard-copy operations
use their separate non-overwriting policy. Validate external structure and
attachment data at the boundary. User-facing transfer behavior is specified in
the [interaction model](../specs/interaction-model.md).
