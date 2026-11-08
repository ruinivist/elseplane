# Persistence

## Library ownership

`LibraryController` owns the immutable published library, pending document
revisions, and one persistence queue. `LibraryStore` reads and writes snapshots
without a second mutable library. Workspace passes editor snapshots to the
library and flushes the outgoing file before replacing its editor. Structural
library operations use the same queue.

## Saving

- Every queued write captures file identity, revision, and snapshot. Failed
  writes retain unsaved state; a late write cannot mark newer content saved.
- Failed loading must not silently overwrite unreadable saved data with an
  empty document.
- Workspace owns the open editor session and forwards document-change
  notifications to the library. File switching flushes completed edits before
  replacement; failed flushes preserve the open editor for retry.

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

Media source strings are raw user content, not a transfer validation boundary.
Clipboard, project, and library decoding preserve them without URL
normalization or source rejection. At runtime, the editor resolves a trimmed
copy for loading or opening, defaulting bare addresses and protocol-relative
addresses to HTTPS; unsupported or unusable sources remain unresolved and are
never requested or opened. Attachment path discovery, image validation,
reference matching, archive validation, and staged publication remain unchanged.

Preserve path, byte-size, archive-entry, image, and attachment-reference
validation. Attachment preparation must not overwrite bytes reachable from the
existing library. Validate external structure and attachment data at the
boundary. Import/restore details and user-facing behavior are specified in the
[interaction model](../specs/interaction-model.md).
