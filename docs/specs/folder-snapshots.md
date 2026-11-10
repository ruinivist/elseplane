# Folder snapshots

Status: proposed. This specification is for design review; it does not replace
the accepted interaction or persistence contracts until accepted.

Related proposals: [architecture design](../arch/folder-snapshots-design.md) and
[ADR 0005](../adr/0005-folder-based-snapshot-transfers.md).

## Scope

Folder snapshots are manual backup, restore, and checkpoint transfers. They do
not link a live folder to a repository and do not watch, synchronize, or delete
remote content. One tree format is used for folders, ZIP files, and GitHub.

An export covers either the current canvas or the whole library. A folder or
repository import always treats its supplied root as the whole candidate tree;
it never treats a chosen subfolder or canvas as an import scope. GitHub imports
cover the whole repository and add recognized content to the local library.

## Acceptance criteria

- Folder, ZIP, and GitHub transfers use one root-relative snapshot format and
  preserve canvas hierarchy and semantic document content. Local imports may
  rebase attachment references to fresh local paths; external media URLs remain
  unchanged, and source image paths do not keep a persistent local identity.
- Imports validate the complete candidate and collect every overwrite decision
  before publishing any part of it. Canceling or failing preserves the library
  and published attachment bytes.
- A local merge keeps unrelated local content. GitHub commits preserve unrelated
  repository content and publish the document and included images in one commit.
- Repository import and current-canvas checkpoint are separate user-triggered
  operations. Each verifies the saved account and repository independently; a
  checkpoint reads its own fresh branch head and bounded tree and never reuses
  an import snapshot.
- A checkpoint rejects tree/object and path-prefix collisions from that fresh
  tree before blob uploads or branch updates. Existing regular output blobs are
  overwritten without content comparison, including shared image paths.
- Missing image files remain unresolved references. Invalid documents, supplied
  corrupt images, unsafe paths, and exceeded limits reject the entire import.
- Transfers remain manual, bounded, and free of credentials or synchronization
  metadata in portable snapshots.

## Behavior

### Snapshot format

The format is a directory tree whose paths are relative to one explicit root.
Each canvas is a pretty-printed, versioned `CanvasDocument` JSON file named
`<full canvas name>.canvas.json`. The file contains the document JSON directly,
not a wrapper. Its local image references stay relative to its parent and point
to sibling files under `attachments/<uuid>.<ext>`.

```text
Sketch.canvas.json
attachments/59a...-....png
Projects/Map.canvas.json
Projects/attachments/59a...-....png
Projects/Empty folder/                 # retained by folder and ZIP snapshots
```

Different parent directories may contain an image with the same UUID path; those
are distinct tree files. A snapshot contains the full relative paths, not only
basenames. A ZIP is a thin wrapper around this tree. Unzip it once and discover
all `.canvas.json` files recursively. Do not inspect nested ZIP files or strip a
top-level directory as a guessed wrapper.

The tree preserves empty directories in folder and ZIP snapshots. Git trees do
not represent empty directories, so GitHub transfers omit empty directories and
do not add marker files for them. Portable transfers contain no local file IDs,
GitHub destination, access token, baseline, or pending-write state.

On web, the proposed direct folder source must include empty directories. It
uses a feature-detected directory picker rather than a file-only folder input;
when directory pickers are unavailable, ZIP remains an explicit alternative,
not a silent fallback. Browser support, secure-context, and permission limits
remain product review points in the [design](../arch/folder-snapshots-design.md).

Local import preserves document meaning and missing-image references, but it
reserves fresh local attachment paths and rebases local references to them.
External media URLs remain untouched. Canvas and explorer-folder paths are
preserved, but attachment filenames can change across import and export.
The fresh-filename recommendation is under review pending the proposed
[root-relative attachment paths](attachment-paths.md) and failure-safe import
integration; it is not an accepted requirement.

### Export

- Current-canvas export includes that canvas, its ancestor directories, and
  available image bytes referenced by the document. It does not include sibling
  canvases. Paths remain relative to the full export root.
- Whole-library export includes the full folder hierarchy, every canvas, and
  available referenced image bytes. It retains empty folders. All paths are
  relative to one root even when only one canvas was selected for export.
- Write each canvas as direct `CanvasDocument` JSON. Include each available
  referenced image once per source tree path, with unchanged bytes. External
  media URLs remain untouched.
- If a referenced image is absent, omit its bytes and retain the reference. A
  storage I/O failure or corrupt image that is present is an export failure;
  it is not treated as a missing file. Reject unsafe paths and the full output
  when validating it fails, before writing an archive or destination.

### Import and local merge

An import discovers every supported canvas file under the supplied root. A
standalone `.canvas.json` is a root canvas. Folder, ZIP, and repository inputs
are full-root inputs, not selected-subtree imports. Unrelated regular files are
ignored; unsafe paths and unsupported file kinds such as links or submodules
fail validation. ZIP entry paths are interpreted literally after one unzip.

For each canvas, remove exactly one final `.canvas.json` suffix to get its full
library name and parent path. Keep spaces and Unicode spelling; do not URL-decode
or silently sanitize names. Resolve each `attachments/...` reference from that
canvas's parent path. Missing image files are allowed and leave references
unresolved. Validate every supplied image and every discovered document before
asking for confirmation.

The library import is an additive union:

- Keep local files and folders absent from the candidate. Reuse matching parent
  folders and create new folders and canvases with new local UUIDs.
- Compare full paths using the library's case-insensitive sibling name rules.
  For a same-path canvas, ask whether to overwrite it. Yes replaces that
  document while retaining its file ID; No aborts the entire import.
- A file-versus-folder or path-prefix conflict is structural. Stop and report
  its path; do not rename, move, or otherwise repair either side automatically.
- Gather every overwrite answer before publishing and outside queued writes. A
  No at any prompt, a validation error, or a changed published-library identity
  or pending revision aborts every replacement and addition. Revalidate when the
  merge enters the queue and after attachment staging, immediately before the
  metadata save; on a late change, remove only unpublished staged bytes. Normal
  saves of completed edits made before the transfer are not rolled back.
- Keep the current file ID and do not select an imported canvas. Overwriting the
  current canvas reinitializes only its editor session after the durable save,
  resetting its history and tools. Discard pending saved revisions only for
  replaced canvases. Do not delete old attachments or retained history data.

### GitHub checkpoints

GitHub is a manual checkpoint transport, not a linked library. Repository import
and checkpoint are mutually exclusive operations started by separate user
actions. Importing reads the whole repository from one immutable default-branch
head and bounded recursive tree, imports all recognized canvases and valid image
files through the shared source and codec, and applies the same additive local
merge above. Repository deletions never delete local files. Existing non-format
files such as `README` and `.gitignore` are ignored. Import never triggers a
checkpoint.

GitHub restore reads only the latest default-branch head. Restoring an earlier
commit or choosing a historical revision is not supported. Restore uses the
same import and local merge operation; it is not a separate replacement mode.

Each checkpoint independently verifies the saved account and repository, then
captures a fresh default-branch head and bounded recursive tree at that
operation's start. It does not reuse an import tree or track a baseline. Encode
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
remote path in place; no delete or cleanup is performed.

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
  characters, duplicate or case-ambiguous paths, file/directory prefix
  conflicts, symbolic links, and unsupported Git objects.
- Preserve names literally. A structural collision between a serialized canvas
  path and another file or folder is an error, not a reason to rename either.
   The `attachments` directory is reserved for images and `.git` for Git
   metadata; real library folders with either name make export fail with the
   conflicting path. Neither becomes an explorer folder on import. These name
   restrictions are proposals for review in the design.
- Validate document JSON with the existing `CanvasDocument` decoder and validate
  image bytes with the existing attachment validator. Preserve unresolved image
  references; do not create a missing-node document type.
- Keep the current 140 MiB maximum for compressed ZIP input/output and total
  uncompressed snapshot content, the 10 MiB image limit, and the 100 MiB
  GitHub blob limit. Enforce declared metadata limits before allocation and
  actual byte limits after reads, counting shared files once per tree path.
  Keep existing bounded GitHub JSON/tree responses and 15-second request
  timeout. Do not promise streaming or lower peak memory use.
- Any invalid document, corrupt supplied image, unsafe path, bad archive, or
  budget overage rejects the whole candidate before confirmation or publication.
  Existing local content and published attachment bytes remain intact.

## Non-goals

There is no live folder link, watcher, background sync, remote deletion
propagation, nested-archive traversal, arbitrary URL download, legacy canvas
format import, automatic remote attachment collision remapping, or portable
GitHub metadata. Fresh local attachment paths and reference rebasing are part of
local staging, not remote collision repair.
