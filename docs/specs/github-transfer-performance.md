# GitHub transfer performance

Status: draft

## Scope

Change how GitHub import reads blobs and how Commit publishes them. Keep the
existing [transfer contract](folder-based-canvas-transfers.md#github-checkpoints)
and [GitHub sync UX](github-sync-ux.md) for selection, confirmation, saving,
commit feedback, and local baselines. Once accepted, update the transfer
contract to replace the recursive-tree import with the archive behavior below.

## Behavior

### Import

- Prepare from a single captured default-branch head. Download one repository
  ZIP pinned to that commit SHA, without fetching a recursive tree or
  individual blobs. A branch change during preparation does not change the
  snapshot for that attempt.
- Validate the ZIP and strip exactly one common top-level directory.
  Use the archive's literal paths and exported bytes as input. An omitted
  file is excluded from import, not a preparation failure. Reject unsafe,
  conflicting, or invalid archive entries; keep the shared document and
  attachment validation. Unrelated regular files in the archive are not
  imported but still count toward its ZIP and transfer size limits. Keep
  the existing GitHub per-file limit and the stricter attachment size limit.
- A canceled attempt returns to Sync immediately and cannot affect the
  workspace or a later attempt, even if its archive download finishes.
  If the archive is unavailable or fails validation, report preparation
  failure. Do not retry via another transport. Preparation never writes
  local data. Saving still requires confirmation.
- Imports from local files, including local ZIPs, retain their current
  behavior.

### Commit

- Verify authorization, capture the live default-branch head and recursive
  tree, and check **all** output paths before performing any remote write.
  Reuse does not permit writes over trees or unsupported objects or through
  a conflicting ancestor.
- For each packaged file, use its exact Git blob ID if the captured tree
  already contains that ID as a regular blob, at any path. Otherwise upload
  the packaged bytes. A matching local baseline, filename, or byte count
  alone is not evidence of a match. Unchanged attachments are still part of
  the resulting checkpoint; they do not need to be uploaded again.
- Publish the complete output mapping in one commit on the captured head.
  Preserve unrelated paths and existing rename or move behavior. Do not
  change whether the app creates a commit merely because it reused all the
  blobs. Do not force the ref update or retry remote writes. A failed or
  uncertain ref update does not advance the local baseline.

## Acceptance criteria

- On a text-only edit with 31 unchanged attachments already in the target
  tree, issue one blob upload. On a new-path byte-identical copy whose
  document and attachments are already in the tree, issue zero. In both cases,
  the resulting tree has the complete expected output and unrelated paths
  remain intact.
- A controlled GitHub import requests one archive at the captured commit
  and no recursive tree or per-file blobs. An archive whose contents match
  the Git tree gives the same result as the previous importer. An omitted
  canvas is not imported and a local copy is not deleted. If an exported
  canvas refers to an omitted image, preserve the reference without an
  alternate download or a local attachment deletion. A canceled fetch,
  unavailable archive, or invalid archive yields no local writes and no
  alternate download.

See [ADR 0009](../adr/0009-speed-up-github-canvas-transfers.md) for the design
trade-offs and the [commit](../plans/github-commit-blob-reuse.md) and
[import](../plans/github-repository-archive-import.md) plans for implementation
and measurement.
