# Use folder-based canvas transfers

Status: accepted

Date: 2026-11-11

## Context

Canvas ZIP export, library ZIP backup, and GitHub canvas transfer currently use
different path layouts and import rules. Canvas projects store one
`document.json`; library archives wrap documents under `library/`; GitHub stores
one `.canvas` file and keeps per-canvas content baselines and pending-write
state. The pre-implementation behavior and the limits of the accepted storage
foundation are recorded in the [historical evidence table](../arch/folder-based-canvas-transfers-design.md#pre-implementation-evidence).

Before this decision, the accepted [document and media ADR 0002](0002-separate-documents-and-media.md),
[persistence contract](../arch/persistence.md), and
[interaction model](../specs/interaction-model.md) defined different transfer
formats, replacement behavior, and single-canvas GitHub workflows. This ADR
accepts the replacement transfer behavior and partially supersedes ADR 0002 as
described below; document/media separation remains in force.

## Decision

Use one provider-independent, root-relative folder tree for current-canvas
exports, whole-library backups, ZIP imports, and manual GitHub checkpoints.
Local input is a standalone `.canvas.json` file or ZIP; local tree exports use
ZIP. The tree stores direct versioned `CanvasDocument` JSON as
`<full canvas name>.canvas.json`; sibling image files live under
`attachments/<uuid>.<ext>` relative to each document's parent. ZIP is only a
container for that same tree.

Local import is additive and best effort. Before writing, validate every input
path and kind, exact duplicates and path-prefix conflicts, local hierarchy
conflicts, finite byte budgets, and ZIP size, checksum, and bounded-inflation
rules. Decode every supported canvas before writes. Skip a canvas with invalid
UTF-8, JSON, or document schema, reporting its path and a sanitized reason; do
not overwrite a local canvas for a skipped document. Source read, network,
path, archive, and size failures reject preparation before import writes. Check
image paths and byte sizes without decoding or sniffing image content.

Keep supplied UUID filenames and relative document references. Write available
image bytes only when referenced by a valid imported canvas, once per resolved
full path, and write them directly to that path. Missing source bytes preserve
the reference and never delete destination bytes. A same-parent full path is a
shared identity: import may replace bytes another canvas uses, including good
bytes with corrupt bytes. Unreferenced images and images referenced only by
skipped canvases do not change local storage.

If valid documents collide with existing canvas paths, list all colliding full
paths in one confirmation dialog with **Overwrite and import** and **Cancel**.
The warning says shared images may also change in other canvases. Do not ask
about images separately or once per canvas. With no canvas collisions, proceed
without a dialog. Cancel means zero import writes. Apply still requires the
exact confirmed path set from preview. In the queue, recheck the captured
library change revision before the first image write and immediately before
metadata save. Stop on the first operational image-write failure, report only
closed writes as confirmed, leave any partial effects in place, and do not save
metadata. After all image writes, save merged metadata once. If that save or a
late change-revision check fails, leave image changes in place and the
previously published library unchanged. Normal saves completed before the
transfer are not rolled back. No local all-or-nothing byte rollback is
promised. One `TransferImportResult` reports skipped canvases, confirmed image
writes, whether metadata was saved, and an optional failure with its stage. It
has no outcome enum; the UI derives no changes from an unchanged merge and no
confirmed image writes.

GitHub repository import covers the whole repository and uses the same local
merge. Import reads only the latest default-branch head, not historical
commits. Import and current-canvas checkpoint use the existing selected
`GitHubDestination` and repository-entry flow; there is no separate import URL
or independently selected import destination. Changing repositories uses the
normal destination flow, and import does not change the saved destination.
Repository import and current-canvas checkpoint are separate manual
operations. Each verifies the saved account and repository independently; a
checkpoint captures its own fresh default-branch head and bounded recursive
tree and never reuses an import source. GitHub commits still publish the current
canvas in one commit and preserve unrelated repository paths. Before blob uploads,
reject an output path occupied by a tree, symlink, submodule, or unsupported
object, and reject a required directory ancestor occupied by a non-directory.
Existing regular output blobs are overwritten blindly, including shared images;
this is structural preservation, not content comparison or conflict resolution.
Local best-effort writes do not change that remote commit behavior. Neither
operation propagates deletions or synchronizes, and import never checkpoints.

Keep the codec under `lib/library/transfer/`, local merge and attachment writes
in `LibraryController`, session and transfer locking in `Workspace`, and GitHub
networking in the GitHub feature. The existing `CanvasProjectFiles` single-file
boundary handles `.canvas.json` and ZIP files; a ZIP adapter implements
`TransferSource`. Do not persist remote content tracking or attachment-name
mappings. Retain path, document, archive, identity, authentication, rate-limit,
and finite-budget validation. Image decoding remains a separate upload concern,
not a transfer prerequisite.
Use existing Workspace composition callbacks to invalidate loaded image
resources by full storage key after image-only writes: refresh confirmed closed
writes and include the failed key only for an image-write failure, since it may
have effects. Do not replace an unchanged editor or clear its history. Preserve
captured keys for pending uploads and pastes. Library values derive each canvas
parent from its file hierarchy. Workspace captures an immutable parent-directory
string for each editor context and passes it to media, text-resource, clipboard,
and upload workflows; the shared codec resolves references from the captured
canvas path. Each asynchronous read or write captures its full key before an
await and keeps that exact key through completion and cleanup. Full keys are
cache identities. ADR 0006 accepted nested byte-store keys only; this ADR
accepts their parent-aware use by callers. That caller adoption is implemented.
The pre-implementation state at baseline `1c4839a` is documented in the
[design's historical evidence](../arch/folder-based-canvas-transfers-design.md#pre-implementation-evidence).
Final demo conversion, obsolete-path removal, automated checks, and required
reviews remain in the [active plan](../plans/folder-based-canvas-transfers.md).

## Hierarchy changes and clipboard

Canvas rename within its parent does not change attachment keys and copies no
image bytes. Moving a canvas, or moving or renaming a folder, copies available
referenced image bytes to the affected canvases' destination-parent paths.
Folder changes remap full parent paths for every descendant canvas. Keep UUID
filenames and document-relative references unchanged, retain source bytes, and
deduplicate identical source/destination key pairs. Never clean up source bytes;
other canvases, history, and clipboard content may still use them.

Before copying, validate all paths and sizes. Keep references unchanged when
source bytes are missing and do not delete destination bytes; an existing file
at the resulting full path may still resolve the reference. A source I/O error
is a failure, not absence. Copy corrupt but available bytes unchanged. If a
destination is absent, copy the source bytes; if it has the same bytes, reuse it
without writing; if it differs, stop and report the conflicting path. This
move/paste policy never overwrites or renames a destination. Compare bytes
directly within the existing 10 MiB limit; do not hash them or add a dependency.
Preflight all known destination-byte conflicts before writes. A later I/O write
failure may leave newly copied bytes, but do not publish a hierarchy change or
pasted elements until all required copies succeed. Save hierarchy metadata
through the existing queue only after copies succeed. On failure, preserve the
original hierarchy and editor; do not add rollback machinery or delete existing
paths.

The internal canvas clipboard payload adds a required, validated
`sourceDirectory` containing the source canvas's root-relative parent path (empty
for the root). Advance the internal payload version and do not add a legacy
decoder. This local origin context and the elements stay in the internal
clipboard JSON; image bytes do not. It is never added to portable
`CanvasDocument` JSON. Copy captures the source parent. Paste captures the
destination parent before awaiting clipboard data, then resolves destination
full keys from the decoded elements before awaiting any copies. Keep the
existing captured destination and session-lifetime checks. Same-parent paste
shares image paths without copying; cross-folder paste copies referenced images
under the same byte-collision policy. External URLs remain unchanged. Existing
element geometry, new IDs, undo behavior, and cut-after-clipboard-write rules
remain unchanged. This does not add cross-device clipboard support or an
embedded-image bundle.

`LibraryController` owns hierarchy copy planning, queue use, and metadata
publication for moves. `CanvasClipboard` owns clipboard context and editor
insertion and does not import `LibraryController`. A minimal byte-only copy
helper may live beside `AttachmentStore`; it receives the store and explicit
source-to-destination full-key pairs, validates and copies bytes, and has no
canvas, library, editor, browser, or registry dependency. Attachment discovery
stays with each caller's owner; it does not require a new layer. Reuse existing
full-key cache invalidation after copied writes, including possible effects of a
failed write, without resetting unchanged editor history. When an active
canvas's path changes, refresh its Workspace context after the durable move;
pending operations remain bound to their captured old full keys and cannot
pollute the new context. Preserve existing asynchronous lifetime guards and
transfer interlocks; do not introduce a new barrier, focus cancellation, or
history reset for an unchanged editor.

## Existing local data prerequisite

The MVP uses only the new nested layout. It has no migration, fallback,
dual-layout branch, persisted mode, detection code, or reset behavior. Existing
root-canvas keys such as `attachments/<uuid>.<ext>` remain valid at the same
root path; the new model must not reinterpret them by adding a folder prefix or
silently lose them. Before testing the new layout locally, the user will manually
clear the app's browser data, including existing canvases and images. No
preservation or conversion task is required for that local testing, and this
does not authorize automatic deletion by the app.

## Alternatives

- Keep separate per-provider formats: rejected because the same library content
  has different representations and validation rules across canvas, library,
  and GitHub transfers.
- Keep GitHub baseline and pending-write state: rejected for the accepted
  overwrite checkpoint model; remote content comparison and recovery UI are
  outside its scope.
- Stage every import image at a fresh path and roll back on failure: rejected
  because changing the supplied identity breaks shared full-path references,
  while restoring overwritten published bytes would require a staging tree,
  version pointers, or a rollback system. Those mechanisms are outside this
  decision. Best-effort local writes instead report confirmed writes and identify
  the failed image key, which may have effects; bounded byte counts do not
  guarantee valid image content.
- Decode corrupt image bytes: rejected because transfers preserve bytes; image
  decoding belongs to upload validation, and runtime rendering contains decode
  failures.
- Use GitHub's single-file contents endpoint: rejected because document and
  attachment updates would not be visible as one commit.
- Add background sync or remote deletion propagation: rejected because this
  design defines explicit transfers, not those GitHub workflows.

## Consequences

This ADR supersedes the transfer-layout and replacement-import portions of ADR
0002, including the former unchanged whole-library ZIP layout. It does not
supersede the separation of document JSON from image bytes, the rejection of
base64 canvas documents, or trust-boundary validation and size limits.

There is no compatibility promise for the prior transfer layout: import accepts
the root-relative tree format only. References without supplied image bytes are
preserved; an existing destination file at the same full path remains available,
and an absent one renders missing. Import and GitHub commit writes preserve
supplied bytes without image-content validation. Import may overwrite a shared
image; the stricter non-overwriting byte-copy rule applies only to moves and
clipboard paste. Partial local writes are not rolled back. Empty folders are
preserved in ZIP archives and cannot be represented in GitHub trees. The
single-commit GitHub branch update remains in force and does not gain local
best-effort cleanup or retry. Folder names `attachments` and `.git` are reserved
case-sensitively as path segments; their case variants remain ordinary names.
Serialized canvas path collisions fail with the offending path. The accepted
interaction and persistence contracts now describe these rules; final
integration and verification are tracked in the active plan.

## Sync UX amendment

The [GitHub sync UX](../specs/github-sync-ux.md) adds local per-canvas baselines
for the title marker. Baselines describe confirmed transfers and stay out of
portable trees. Transfer formats, import publication, and remote branch
updates retain the rules in this decision.

## Supersedes or superseded by

Supersedes the transfer-format and replacement-import portions of
[ADR 0002](0002-separate-documents-and-media.md). Document/media separation,
relative references, and the associated validation rationale remain accepted.
