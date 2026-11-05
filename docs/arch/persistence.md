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

## Staged import protocol

Validate the complete candidate, confirm replacement, flush current edits,
suspend conflicting writes, prepare every imported attachment at a fresh unused
path, persist metadata, then publish state. Canvas import, library restore, and
debug Demo creation share this staging path. Failure preserves existing live
content; cleanup attempts only new unpublished attachment paths. Successful
replacement invalidates queued revisions from the outgoing document. Existing
attachments remain available to saved documents and retained history.

Preserve path, byte-size, archive-entry, image, and attachment-reference
validation. Attachment preparation must not overwrite bytes reachable from the
existing library. Validate external input at the boundary. Import/restore
details and user-facing behavior are specified in the
[interaction model](../specs/interaction-model.md).
