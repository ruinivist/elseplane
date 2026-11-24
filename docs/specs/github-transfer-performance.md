# GitHub transfer performance

Status: draft

## Scope

Change how GitHub import reads blobs and how Commit publishes them. Keep the
existing [transfer contract](folder-based-canvas-transfers.md#github-checkpoints)
and [GitHub sync UX](github-sync-ux.md) for selection, confirmation, saving,
commit feedback, and local baselines.

## Behavior

### Import

- Prepare from one captured default-branch commit and its validated
  recursive tree. Fetch supported blobs by ID directly from GitHub, as
  raw bytes. A later branch change does not change the snapshot.
- Allow at most eight blob requests in flight per attempt. Fetch each
  distinct blob ID once per attempt and preserve all its original paths.
  Validate each successful response against its declared size and Git
  blob ID. Preserve normal HTTP error handling even for zero-byte blobs.
  Keep existing path, per-entry, attachment, and aggregate byte limits;
  shared blobs still count once per literal path toward the byte budget.
  Completion order must not change the merge or skip report.
- Cancel returns to Sync immediately. Cancellation or a terminal read
  error stops scheduling new reads. Already-started requests may finish,
  but their results must not affect the workspace or a later attempt.
  Report a terminal read or integrity failure before any writes, without
  retries or another transport. Saving still requires confirmation.
- Imports from local files, including local ZIPs, retain their current
  behavior.

### Rate limits

When GitHub rate-limits an active operation, stop it and advise when to
try again. Use GitHub's wait time if available; otherwise advise waiting
a minute. Do not retry automatically, or impose a shared client cooldown
on later explicit operations.

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
- A controlled GitHub import overlaps blob requests, never exceeds eight
  in flight, and fetches each requested ID once even if multiple paths use
  it. Out-of-order completion produces the same result as sequential
  import. Cancellation or invalid bytes yield no writes and no fallback
  download; a fresh attempt is unaffected by late responses.

See [ADR 0009](../adr/0009-speed-up-github-canvas-transfers.md) for the design
trade-offs and the [commit](../plans/github-commit-blob-reuse.md) and
[import](../plans/github-parallel-blob-import.md) plans for implementation
and verification.
