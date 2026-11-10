# Use folder snapshots for backup and remote checkpoints

Status: proposed

Date: 2026-11-10

## Context

Canvas ZIP export, library ZIP backup, and GitHub canvas transfer currently use
different path layouts and import rules. Canvas projects store one
`document.json`; library archives wrap documents under `library/`; GitHub stores
one `.canvas` file and keeps per-canvas content baselines and pending-write
state. The details are in the [folder snapshot specification](../specs/folder-snapshots.md)
and [design](../arch/folder-snapshots-design.md).

The accepted [document and media ADR 0002](0002-separate-documents-and-media.md),
[persistence contract](../arch/persistence.md), and
[interaction model](../specs/interaction-model.md) define different current
formats, replacement behavior, and single-canvas GitHub workflows. This ADR is
only a proposal. It does not silently change those accepted contracts.

## Decision

Propose one provider-independent, root-relative folder tree for current-canvas
exports, whole-library backups, folder and ZIP imports, and manual GitHub
checkpoints. The tree stores direct versioned `CanvasDocument` JSON as
`<full canvas name>.canvas.json`; sibling image files live under
`attachments/<uuid>.<ext>` relative to each document's parent. ZIP is only a
container for that same tree.

Local import is additive, validates the complete tree, gathers every overwrite
answer before publication, and stages available images at fresh local paths.
GitHub repository import covers the whole repository and uses the same local
merge. Restore reads only the latest default-branch head, not historical
commits. Repository import and current-canvas checkpoint are separate manual
operations. Each verifies the saved account and repository independently; a
checkpoint captures its own fresh default-branch head and bounded recursive
tree, never an import snapshot. GitHub commits publish the current canvas in one
commit and preserve unrelated repository paths. Before blob uploads, reject an
output path occupied by a tree, symlink, submodule, or unsupported object, and
reject a required directory ancestor occupied by a non-directory. Existing
regular output blobs are overwritten blindly, including shared images; this is
structural preservation, not content comparison or conflict resolution. Neither
operation propagates deletions or synchronizes, and import never checkpoints.

Keep the codec under `lib/library/transfer/`, local merge and attachment
staging in `LibraryController`, session and transfer locking in `Workspace`,
and network and OAuth work in the GitHub feature. Propose feature-detected
`showDirectoryPicker()` for direct browser folder reads and writes; retain the
existing single-file picker for `.canvas.json` and ZIP. Do not use a lossy
file-only folder picker, persist directory handles, or persist remote content
tracking or attachment-name mappings. Retain path, document, image, archive,
identity, authentication, rate-limit, and finite-budget validation.

## Alternatives

- Keep separate per-provider formats: rejected because the same library content
  has different representations and validation rules across canvas, library,
  and GitHub transfers.
- Keep GitHub baseline and pending-write state: rejected for the proposed
  overwrite checkpoint model; remote content comparison and recovery UI are
  outside its scope.
- Use GitHub's single-file contents endpoint: rejected because document and
  attachment updates would not be visible as one commit.
- Add live linked folders or background sync: rejected because this design is
  for explicit snapshots and does not define remote deletion or conflict
  propagation.

## Consequences

On acceptance, this ADR supersedes the transfer-layout and replacement-import
portions of ADR 0002, including the stated unchanged
whole-library ZIP layout. It does not supersede the separation of document JSON
from image bytes, the rejection of base64 canvas documents, or trust-boundary
validation and size limits.

Acceptance also requires explicit alignment of the accepted persistence and
interaction contracts, which currently require destructive library restore and
single-canvas GitHub transfers. Until then, those documents remain authoritative.
There is no backward-compatibility promise for existing transfer files at this
development stage. Missing image references remain unresolved. Local import
preserves semantic document content but may rebase attachment references to
fresh local paths; external media URLs remain untouched, and source image paths
have no persistent local identity mapping. External folder writes may be partial
on failure. Empty folders cannot be represented in GitHub trees.

Direct browser folder support remains a product review point: directory pickers
have limited browser availability, require a secure context and permission, and
must be invoked in a user gesture. ZIP is an explicit alternative, not a silent
folder fallback. Empty-directory output policy, repository-root URL syntax,
the reserved `attachments` and `.git` names, and changes to attachment filenames also need
review; they are not accepted behavior under this proposed ADR.

## Supersedes or superseded by

If accepted, supersedes the transfer-format and replacement-import portions of
[ADR 0002](0002-separate-documents-and-media.md). It does not currently
supersede any accepted document; no authority changes until explicit
acceptance.
