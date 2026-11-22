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

The browser store uses IndexedDB: one document record per canvas, separate
library metadata, and canvas-only autosaves that write only changed documents.
Library operations that change both records and metadata commit them in one
transaction. [ADR 0007](../adr/0007-store-canvases-individually-in-indexeddb.md)
records the decision, and the [browser canvas persistence specification](../specs/browser-canvas-persistence.md)
defines save and load behavior. Old `localStorage` libraries are not migrated.

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

The local library snapshot stores the selected GitHub destination and retains
the legacy `githubImportPromptPending` boolean to preserve the existing metadata
format. That field is inert: the UI and transfer workflow ignore it, and normal
library updates preserve its stored value. Each canvas can store one baseline
with its account, repository, branch, canvas path, SHA-256 of the canonical
document, and hashes of the referenced attachment bytes present in the transfer.
A missing baseline represents an uncommitted canvas once a destination is
selected. Portable transfers contain no GitHub metadata.

GitHub compares the local path and document before reading attachments and
discards an asynchronous comparison when its canvas, destination, or bytes
change. GitHub import publishes baselines with the merged library after
attachment writes succeed. Commit records its captured version through the
library queue after the remote branch update is confirmed. A local save
failure leaves the previous baseline and reports the remote success and local
failure together. An uncertain remote update leaves the baseline intact.
Installation discovery and credentials stay in memory. Every transfer
revalidates its destination and the current default branch.

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
