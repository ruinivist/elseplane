# Folder-based canvas transfers

Status: accepted.

Related accepted decision and design: [ADR 0005](../adr/0005-folder-based-canvas-transfers.md)
and [architecture design](../arch/folder-based-canvas-transfers-design.md).

## Scope

Folder-based canvas transfers support manual import, export, and GitHub
checkpoints through one root-relative tree format. Local input is a standalone
`.canvas.json` file or ZIP; local exports use ZIP. GitHub repository imports and
checkpoints use the whole repository and the current canvas, respectively.

An export covers either the current canvas or the whole library. A ZIP or
repository import always treats its supplied root as the whole candidate tree;
it never treats a selected subtree as an import scope. A standalone
`.canvas.json` imports as a root canvas. GitHub imports cover the whole repository
and add recognized content to the local library.

## Acceptance criteria

- ZIP and GitHub transfers use one root-relative format and preserve canvas
  hierarchy and valid document content; a standalone `.canvas.json` imports at
  the root. Local imports retain literal attachment filenames and relative
  references; external media URLs remain unchanged.
- Local ZIP exports retain the download names `canvas.elseplane.zip` and
  `library.elseplane.zip` for current-canvas and whole-library scope,
  respectively, and use the `application/zip` media type.
- Before import writes, validate all paths, entry kinds, exact duplicate paths,
  prefix collisions, local hierarchy conflicts, and finite byte budgets. Paths
  differing only by case remain distinct. ZIP input must pass bounded inflation,
  declared and actual size checks, and
  checksums. Source read, network, archive, path, and size failures reject the
  candidate before import writes.
- Skip an individual canvas with invalid UTF-8, JSON, or document schema only
  after its path, size, and archive integrity checks pass. Report its path and a
  sanitized reason. Never use a broad parse catch to hide source or budget
  failures, and never load skipped document state.
- Check image paths and byte limits without decoding or sniffing image content.
  Write available bytes only for references in valid imported canvases, once per
  full source path. Unreferenced images and images referenced only by skipped
  canvases do not change local storage. Missing source bytes preserve the saved
  reference and never delete destination bytes.
- Local imports are additive. List all valid canvas-path collisions in one
  confirmation dialog with **Overwrite and import** and **Cancel**; the warning
  says shared images may change in other canvases. Do not ask per canvas or ask
  separately about images. With no canvas collisions, proceed without a dialog.
  Cancel aborts all import writes. One `TransferImportResult` reports
  skipped canvases, confirmed closed image writes, whether metadata was saved,
  and an optional failure with stage, path, and sanitized reason. A write or
  metadata failure may leave image bytes changed and does not trigger rollback
  or cleanup.
- A local merge keeps unrelated local content. GitHub commits preserve unrelated
  repository content and publish the document and included images in one commit.
- Repository import and current-canvas checkpoint are separate user-triggered
  operations. Each verifies the saved account and repository independently,
  including fresh membership in the selected GitHub App installation; a
  checkpoint reads its own fresh default-branch head and bounded tree and never
  reuses an import transfer.
- GitHub App OAuth uses the existing mediator and expiring user access tokens;
  tokens remain in memory and authorization does not depend on a `repo` scope.
  Discovery lists repositories from accessible installations of this app. The
  installation screen controls the GitHub grant, while one searchable setup
  picker sets the single saved `GitHubDestination` for both Import and Commit.
  The installation ID is transient and is not part of saved library metadata.
  After reload, resolve the saved account/repository identity against current
  discovery before enabling transfers. Import and Commit display and use that
  saved choice; neither prompts for another repository or changes the selection.
  Import uses the latest default branch and the whole repository. There is no
  separate import URL or destination.
- Transfers use only the current default branch. Verify membership in the
  selected installation and the repository/account identity before transfer;
  do not enumerate other installations for this check or treat the installation
  ID as authorization. If the default branch changed since selection, require
  refresh and explicit confirmation rather than switching silently. Reject a
  repository with no default-branch commit and confirm emptiness with a bounded
  branch query rather than repository size. The user-facing error is: "This
  repository is empty. Add a README on GitHub, then refresh." Empty repositories
  cannot be imported or committed, and no files, branches, or commits are created
  to initialize them.
- A checkpoint rejects tree/object and path-prefix collisions from that fresh
  tree before blob uploads or branch updates. Existing regular output blobs are
  overwritten without content comparison, including shared image paths.
- Missing source images leave references unchanged and existing destination
  bytes intact. Corrupt image bytes are accepted within the byte limits;
  rendering contains decode failures and shows
  a missing or broken image state rather than crashing.
- Transfers remain manual, bounded, and free of credentials or synchronization
  metadata in portable transfers.
- Canvas rename within its parent copies no image bytes. Moving a canvas or
  moving or renaming a folder copies available referenced images to the affected
  canvases' destination-parent keys without changing UUID filenames or document
  references. Source bytes remain available.
- Move and cross-folder paste reuse a destination only when its bytes match the
  source; they never overwrite or rename a differing destination. Preflight all
  known byte conflicts, and do not publish hierarchy changes or pasted elements
  until required copies succeed. Failed writes may leave newly copied bytes.
- Internal canvas clipboard JSON carries a required validated root-relative
  `sourceDirectory`; portable `CanvasDocument` JSON does not. Cross-folder paste
  copies referenced images, while same-parent paste shares them. The clipboard
  remains local and does not embed image bytes.
- Before testing the new layout locally, the user will manually clear the app's
  browser data, including existing canvases and images. No migration or automatic
  reset is part of this MVP.

## Behavior

### Transfer format

The format is a directory tree whose paths are relative to one explicit root.
Each canvas is a pretty-printed, versioned `CanvasDocument` JSON file named
`<full canvas name>.canvas.json`. The file contains the document JSON directly,
not a wrapper. Its local image references stay relative to its parent and point
to sibling files under `attachments/<uuid>.<ext>`.

Keep the existing lowercase version-4 UUID filename and `.png`, `.jpg`, `.gif`,
or `.webp` extension rules from the accepted
[attachment path specification](attachment-paths.md). A full transfer path is
that relative reference joined to the canvas's parent path.

```text
Sketch.canvas.json
attachments/59a...-....png
Projects/Map.canvas.json
Projects/attachments/59a...-....png
Projects/Empty folder/                 # retained by ZIP transfers
```

Different parent directories may contain an image with the same UUID path; those
are distinct tree files. A transfer tree contains the full relative paths, not only
basenames. A ZIP is a thin wrapper around this tree. Unzip it once and discover
all `.canvas.json` files recursively. Do not inspect nested ZIP files or strip a
top-level directory as a guessed wrapper.

Library names and transfer paths compare literally and case-sensitively:
`School/Map.canvas.json` and `school/Map.canvas.json` are distinct paths, while
an exact duplicate path is invalid. ZIP preserves the entry spellings, but
extracting it onto a case-insensitive filesystem may fail or collapse
case-distinct paths; this specification defines no alternate export naming mechanism.

The tree preserves empty directories in ZIP transfers. Git trees do not
represent empty directories, so GitHub transfers omit them and do not add marker
files. Portable transfers contain no local file IDs, GitHub destination, access
token, baseline, or pending-write state.

Local import preserves canvas-relative references and writes available image
bytes to their exact full paths beneath the import root. A same-parent reference
identifies the same shared bytes; the same relative reference in another parent
identifies different bytes. A write can therefore replace bytes used by another
canvas at that full path, including replacing valid bytes with corrupt bytes.
This is shared-byte replacement, not automatic forking or a new image-editing
behavior. There is no fresh-name allocation, rebasing, or filename map. Missing
source bytes do not delete or replace destination bytes. External media URLs
remain untouched.

This accepted specification adopts nested keys in transfer and editor callers.
ADR 0006 remains the byte-store foundation. At pre-implementation baseline
`1c4839a`, callers still used root-level keys; parent-aware caller adoption is
now implemented. The [design's caller
adoption and remaining integration gates](../arch/folder-based-canvas-transfers-design.md#caller-adoption-and-remaining-integration-gates)
records the selected ownership and behavior. The MVP uses only the new nested
layout: there is no old-layout fallback, dual-layout branch, migration, persisted
mode, detection, or reset. Existing root-canvas keys such as
`attachments/<uuid>.<ext>` remain valid at the same root path; do not add a
folder prefix or silently lose their bytes. For local testing of the new layout,
the user will manually clear the app's browser data, including existing canvases
and images. This does not authorize automatic deletion by the app.

### Export

Local exports are ZIP archives of the transfer tree. Current-canvas export
downloads as `canvas.elseplane.zip`; whole-library export downloads as
`library.elseplane.zip`. Both use the `application/zip` media type.

- Current-canvas export includes that canvas, its ancestor directories, and
  available image bytes referenced by the document. It does not include sibling
  canvases. Paths remain relative to the full export root.
- Whole-library export includes the full folder hierarchy, every canvas, and
  available referenced image bytes. It retains empty folders. All paths are
  relative to one root even when only one canvas was selected for export.
- Write each canvas as direct `CanvasDocument` JSON. Include each available
  referenced image once per source tree path, with unchanged bytes, without
  image decoding or format sniffing. External media URLs remain untouched.
- If a referenced image is absent, omit its bytes and retain the reference. A
  storage I/O failure is an export failure; it is not treated as a missing file.
  Copy corrupt but available bytes unchanged. Reject unsafe paths and the full
  output when validating it fails, before writing an archive or destination.

### Import and local merge

An import discovers every supported canvas file under the supplied root. A
standalone `.canvas.json` is a root canvas. ZIP and repository inputs are
full-root inputs, not selected-subtree imports. Unrelated regular files are
ignored; unsafe paths and unsupported file kinds such as links or submodules
fail validation. ZIP entry paths are interpreted literally after one unzip.

For each supported canvas path, remove exactly one final `.canvas.json` suffix
to get its full library name and parent path. Keep spaces and Unicode spelling;
do not URL-decode or silently sanitize names. Validate all entries, full paths,
exact duplicate paths, path-prefix conflicts, local hierarchy conflicts,
and byte budgets before asking for confirmation or writing. ZIP entries must
also pass bounded inflation and checksum checks. Validate every recognized
image's path and size, but do not decode its bytes. Missing referenced images
are allowed: preserve the reference, use existing destination bytes if present,
and otherwise show a missing image.

Decode every supported canvas before writes. Invalid UTF-8, JSON, or document
schema skips only that canvas and adds a `TransferIssue` with its path and a
sanitized reason to `TransferImport.skippedCanvases`. Do not overwrite a local
canvas for a skipped source document. Keep read, network, size, path, and archive
integrity failures outside the document-parser catch: those fail preparation and
cause zero import writes. Unknown document schema versions are skipped.

The codec may read and integrity-check recognized attachment entries that will
not be stored. Only bytes referenced by valid imported documents are eligible
for local writes. Ignore unrelated regular files after validating their entry
paths, kinds, and budgets. Reserve literal case-sensitive `attachments` and
`.git` folder segments: they cannot become explorer folders. Exclude `.git`
metadata from discovery without treating ordinary Git metadata as an error.

The library import is an additive union:

- Keep local files and folders absent from the candidate. Reuse matching parent
  folders and create new folders and canvases with new local UUIDs. Preserve
  local-only library settings such as the saved GitHub destination; portable
  transfers do not supply those settings or local IDs.
- Compare full paths case-sensitively, matching only exact spelling. List all
  valid same-path canvas collisions in one dialog. Its buttons are **Overwrite
  and import** and **Cancel**; the warning says shared images may also change in
  other canvases. There is no per-canvas question, selective skip, or separate
  image prompt. With no canvas collisions, continue without a dialog. Confirmed
  overwrites replace documents while retaining their file IDs; Cancel aborts
  the entire import with zero writes. The apply operation still requires the
  exact confirmed path set.
- A file-versus-folder or path-prefix conflict is structural. Stop and report
  its path before overwrite confirmation or writes; do not rename, move, or
  otherwise repair either side automatically.
- Gather the single overwrite confirmation before writes and outside the
  persistence queue. Cancel aborts with zero import writes. Capture the
  monotonic library change revision in preview after flushing prior edits.
  Recheck it at queue entry before the first image write and immediately before
  metadata save. A mismatch before writes is a preparation failure; a mismatch
  after writes is a publication failure, and already-written image bytes remain.
  Normal saves of completed edits made before the transfer are not rolled back.
- In the queue, write available referenced image bytes at their exact full paths
  in deterministic path order. Stop at the first operational write failure. The
  report includes only writes whose close completed. The failure path for an
  image-write failure is the actual attempted key and may have effects; later
  eligible paths are derived from the candidate's deterministic key order and
  are not stored as another report list. Do not remove or roll back any changed
  bytes and do not save metadata after an image-write failure. If all image
  writes succeed, save merged metadata once. A metadata-save failure leaves image
  changes in place and the previously published library unchanged.
- `TransferImportResult` has `skippedCanvases`, `writtenImagePaths`,
  `metadataSaved`, and optional `failure`. A failure has a sanitized `reason`,
  an optional `path`, and a stage of preparation, image write, or publication.
  Only an image-write failure has a path that is an attempted image key; it may
  have effects but is not included in `writtenImagePaths`. Preparation failures
  can identify a bad input path, while publication failures cover a late change
  or metadata-save failure. The coordinator catches expected operational
  preparation errors and returns this same report; it does not turn programmer
  defects into input failures. The user interface retains its own knowledge of
  cancellation and does not encode it as another result outcome. On cancel, do
  not apply the merge; retain skipped-canvas issues, with no writes, no metadata
  save, and no failure. Derive a no-changes state from candidate changes and
  confirmed writes, not as a success outcome. Show imported-canvas or folder
  summaries from the candidate only when `metadataSaved` is true. Empty-folder
  additions can save metadata even without image writes. No automatic retry or
  rollback is promised.
- Keep the current file ID and do not select an imported canvas. Overwriting the
  current canvas reinitializes only its editor session after the successful
  metadata save, resetting its history and tools. Discard pending saved revisions
  only for replaced canvases after durable success. Do not delete old attachments
  or retained history data.
- Image-only changes, including writes that may have taken effect before a
  failure, invalidate loaded media and Markdown image resources by full storage
  key through existing Workspace composition callbacks. Always invalidate
  confirmed written keys, including after a publication failure; on an
  image-write failure, also invalidate its failed key because it may have
  changed. Do not infer attempted paths for preparation
  or publication failures. This includes refreshing Flutter image-cache identity
  when needed. Keep an unchanged editor and its history; reopening is not
  required. Missing or broken cached entries must be retried after invalidation.
  Pending uploads and pastes keep their captured key and lifetime; the transfer
  interlock does not cancel work already in flight.

### Moves and cross-folder clipboard paste

Library rename or move behavior keeps canvas-relative image references
unchanged. Renaming a canvas within its parent does not change any image key and
copies no bytes. Moving a canvas copies each available referenced image to its
destination parent's full key. Moving or renaming a folder does the same for
every descendant canvas using each canvas's remapped full parent path. Keep the
UUID filename, retain source bytes for other canvases, history, or clipboard
content, and deduplicate identical source/destination key pairs. Never remove
source bytes as cleanup.

Validate all source and destination paths and image sizes before I/O. If source
bytes are missing, keep the reference unchanged and do not delete destination
files; as with imports, bytes already present at the resulting full destination
key may still resolve that reference. A source read I/O error is a failure, not
absence. Copy corrupt but available bytes unchanged without image decoding.
When the destination is absent, copy the bytes. When it contains identical
bytes, reuse it without rewriting. When it contains different bytes, stop and
report the conflicting full path; do not rename, overwrite, or ask for a
conflict-resolution choice. Compare bytes directly, within the existing 10 MiB
limit, without hashing or a new dependency. Deduplicate source/destination pairs.

Preflight all known destination-byte conflicts before writing. A later write
failure may leave newly copied bytes, but the hierarchy change or pasted
elements must not be published until every required copy succeeds. Do not add
rollback machinery or delete existing paths. Save a successful hierarchy change
through the existing `LibraryController` queue only after copying succeeds. On
copy or metadata-save failure, keep the original hierarchy and editor state.
Existing cycle, exact sibling-name, reserved-name, and serialized-path conflict
rules reject the operation with the offending path where applicable.

The internal canvas clipboard JSON adds a required, validated
`sourceDirectory`: the source canvas's root-relative parent path, with `''` for
the root. Advance the internal payload version and do not add a legacy decoder.
This origin context is local clipboard metadata, not a field in portable
`CanvasDocument` JSON. Image bytes are not embedded. Copy captures the source
parent; paste captures its destination parent before awaiting the clipboard,
then resolves destination full keys from the decoded elements before awaiting
copies. Retain the existing captured destination and session-lifetime checks.
Same-parent paste shares image paths without copying; cross-folder paste copies
referenced images under the policy above. External URLs remain unchanged.
Keep selected-element geometry, generated IDs, undo behavior, and Cut's
delete-after-successful-clipboard-write rule unchanged. Do not wait for pending
asynchronous work under a new policy. This is not cross-device clipboard support
or an embedded-image bundle.

### GitHub checkpoints

GitHub is a manual checkpoint transport, not a linked library. Repository import
and checkpoint are mutually exclusive operations started by separate user
actions. Both display and use the saved `GitHubDestination`; neither prompts for
or changes the repository selection. One searchable setup picker saves an
explicit choice for both actions. Search only filters the current list of
repositories discovered from accessible installations of the configured GitHub
App. GitHub's installation screen controls the grant; the app picker does not
change it. Import uses the latest default branch and the whole repository; it
does not accept a separate URL or independently selected destination. Importing
reads the repository from one immutable default-branch head and bounded recursive
tree, imports supported canvas files and recognized image paths through the
shared source and codec, and applies the same additive local merge above.
Repository deletions never delete local files. Existing non-format files such as
`README` and `.gitignore` are ignored. Import never triggers a checkpoint.

The mediator's existing OAuth flow supplies expiring GitHub App user access
tokens. Access tokens and installation IDs stay in memory; the persisted
destination contains no installation ID. A reload resolves the saved account and
repository against fresh discovery before enabling transfers. No `repo`-scope
gate is used. A transfer receives the selected installation ID as required
operation context and freshly verifies membership only within that installation,
as well as the account, repository ID, and default branch. The ID alone is not
proof of authorization; a membership lookup failure fails closed. Do not
enumerate unrelated installations during transfer verification or add an
authorization cache.

GitHub import reads only the latest default-branch head. Importing an earlier
commit or choosing a historical revision is not supported. Import uses the same
local merge operation; it is not a separate replacement mode.

Each checkpoint independently verifies the saved account and repository and
freshly checks membership in the selected installation, then captures a fresh
default-branch head and bounded recursive tree at that operation's start. It
does not reuse an import tree or track a baseline. Encode
the captured current canvas and publish it with all included image bytes in one
commit. The document path mirrors its full local parent path and name with
`.canvas.json`; image paths are relative to that document's parent. Before
uploading blobs, validate the proposed paths against the freshly captured tree:

- An output file may overwrite an existing regular blob without comparing its
  contents. This includes shared image paths, so another remote canvas that
  references a shared path sees the new bytes.
- Reject an output path occupied by a tree, symlink, submodule, or other
  unsupported Git object. Also reject any required directory ancestor occupied
  by a non-directory. Report the conflicting path; do not repair it or show a
  repair flow.
- These structural checks prevent replacing a directory or reserved
  `attachments` file/tree and dropping unrelated files. A structural failure
  happens before blob uploads and never updates the branch. It is not a content
  comparison or conflict-resolution policy.

Build one tree on the fresh head, create one commit, and update only the selected
default-branch reference. Unrelated repository files remain in the tree.
Renaming or moving a local canvas publishes the new path and leaves the old
remote path in place; no delete or cleanup is performed. Local best-effort image
writes do not weaken GitHub's one-commit branch update or add local rollback,
remote cleanup, or retry behavior.

Keep the current explicit commit-message requirement: a nonempty lowercase
Conventional Commit subject of at most 72 characters.

There is no remote content baseline, per-canvas tracking, pending-write guard,
remote attachment collision remapping, force push, conflict UI, or automatic
retry. A branch race may reject the commit. If the result is uncertain, report
that it may have succeeded and show its link. Do not retry automatically. A user
may submit again; GitHub may then contain another identical history commit.

Keep the existing GitHub account and repository identity checks, in-memory
session credentials, cookie-enabled mediator separation, sanitized errors,
rate-limit handling, and finite response and time budgets. Portable data never
contains credentials.

### Validation and failure boundaries

- Reject absolute paths, empty, `.` or `..` segments, backslashes, control
  characters, exact duplicate paths, file/directory prefix
  conflicts, symbolic links, and unsupported Git objects.
- Preserve names literally and case-sensitively. A structural collision between
  a serialized canvas path and another file or folder fails with its path; do
  not rename either side. Literal folder segments `attachments` and `.git` are
  reserved: reject them when creating, renaming, or moving a library folder and
  in an input tree when applicable. A real library folder with either name
  makes export fail with its path. Exclude `.git` metadata from input discovery;
  ordinary Git metadata is not an error and neither reserved folder becomes an
  explorer folder. Case variants such as `Attachments` remain valid. A canvas
  title may be `attachments` or `.git` when its serialized file path does not
  collide.
- Validate document JSON with the existing `CanvasDocument` decoder. Skip
  malformed or unsupported-schema canvas documents with a path and sanitized
  reason; never construct invalid document state. Validate image paths, archive
  integrity, and byte sizes, but do not decode images as a transfer prerequisite.
  Preserve unresolved image references; do not create a missing-node document
  type. Image upload validation outside transfers is unchanged.
- Keep the current 140 MiB maximum for compressed ZIP input/output and total
  uncompressed transfer content, the 10 MiB image limit, and the 100 MiB
  GitHub blob limit. Enforce declared metadata limits before allocation and
  actual byte limits after reads, counting shared files once per tree path.
  Keep existing bounded GitHub JSON/tree responses and 15-second request
  timeout. Do not promise streaming or lower peak memory use.
- Unsafe paths, unsupported entry kinds, exact duplicate paths,
  local structural conflicts, bad archive integrity, source read or network
  errors, and budget overages reject preparation before confirmation or import
  writes. Invalid document bytes or schema skip only their canvas after those
  checks. Corrupt image content is not decoded or rejected. Local image writes
  and metadata saves can fail after some image paths have changed; reports do not
  promise rollback or untouched failed paths.

## Non-goals

There is no background sync, remote deletion propagation, nested-archive
traversal, arbitrary URL download, legacy canvas format import, automatic remote
attachment collision remapping, or portable GitHub metadata. Local imports do
not allocate replacement attachment names, rebase references, roll back shared
bytes, or promise all-or-nothing storage.
