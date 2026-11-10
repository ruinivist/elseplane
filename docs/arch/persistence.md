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

This storage foundation does not adopt nested keys in current callers. They
continue using root-level keys, including for canvases in nested explorer
folders. Canvas-relative references remain unchanged. Import and restore keep
the existing fresh-path staging and publication protocol, with cleanup limited
to new unpublished attachments.

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

## Canvas archives

The accepted [document and media decision](../adr/0002-separate-documents-and-media.md)
defines single-canvas transfers. The ZIP contains pretty-printed,
versioned `CanvasDocument` JSON directly in `document.json` and each referenced
local image once under its relative `attachments/<uuid>.<extension>` path;
media bytes remain unchanged and external URLs stay external. Remote media
persists only its source URL and geometry; there is no saved display kind.
Provider metadata and thumbnail previews are runtime-only and do not enter
document JSON or ZIP files. The ZIP is a download container, not a document
format. Do not support base64 JSON canvas transfers. The whole-library ZIP
layout is unchanged. See the accepted
[media link cards decision](../adr/0003-media-link-cards-without-embeds.md).

Before expanding entries, allow only the expected document and image paths,
reject duplicates, unsafe paths, and symlinks, and check declared sizes. After
expansion, verify actual sizes and checksums, then validate document values,
image bytes, and attachment references. Limit the compressed archive and total
uncompressed content to 140 MiB each, and each image to 10 MiB. Import confirms
replacement, stages attachments at fresh unused paths, and remaps references;
cancellation or failure preserves existing content and attachments.

## Staged import protocol

Validate the complete candidate, confirm replacement, flush current edits,
suspend conflicting writes, prepare every imported attachment at a fresh unused
path, persist metadata, then publish state. Canvas import, library restore, and
debug Demo creation share this staging path. Failure preserves existing live
content; cleanup attempts only new unpublished attachment paths. Successful
replacement invalidates queued revisions from the outgoing document. Existing
attachments remain available to saved documents and retained history.

## GitHub metadata

The browser library snapshot may include a shared GitHub destination (account
and repository identities plus owner, repository, and branch) and per-canvas
last-confirmed tracking (remote path, document and attachment blob SHAs, and
attachment-name mapping) plus optional pending tracking for an intended write.
These are non-secret local metadata; access tokens remain in memory. Older
snapshots without these optional fields load without a destination or tracking.
Changing the account, repository, or branch clears both tracking values without
changing documents. Logging out retains the destination and tracking for a
later reconnection.

Canvas document and ZIP transfers contain no GitHub destination, tracking, or
write guard. Restoring a portable library backup therefore does not restore a
GitHub connection or commit baseline.

Before a commit updates the remote branch reference, the GitHub feature
orchestrator persists the last-confirmed tracking unchanged and the proposed
tracking as pending. A confirmed result advances the confirmed baseline and
clears pending tracking; a definitive pre-update failure clears pending
tracking. If the reference update may have succeeded, or GitHub succeeds but
the final local tracking save fails, pending tracking remains durable and
blocks another write. The user must explicitly check remote status: a fresh
repository snapshot either confirms the pending document and attachment SHAs,
or verifies the prior baseline and an unused proposed path (including an absent
first-publication path) before allowing a manual retry. Other remote states keep
the guard and can be imported as another canvas. Never automatically retry an
uncertain remote write. GitHub imports validate the canvas and referenced
attachments, stage fresh local attachment paths, and ask the library to persist
the imported canvas, folders, and tracking in one write; a related pending guard
is cleared only by that successful write. Failure leaves published library
state unchanged.

Media source strings are raw user content, not a transfer validation boundary.
Clipboard, project, and library decoding preserve them without URL
normalization or source rejection. At runtime, the editor resolves a trimmed
copy for loading or opening, defaulting bare addresses and protocol-relative
addresses to HTTPS; unsupported or unusable sources remain unresolved and are
never requested or opened. Canvas-relative attachment-reference discovery,
image validation, archive validation, and staged publication remain unchanged.
Storage-key validation follows the accepted
[attachment path specification](../specs/attachment-paths.md).

Preserve path, byte-size, archive-entry, image, and attachment-reference
validation. Attachment preparation must not overwrite bytes reachable from the
existing library. Validate external structure and attachment data at the
boundary. Import/restore details and user-facing behavior are specified in the
[interaction model](../specs/interaction-model.md).
