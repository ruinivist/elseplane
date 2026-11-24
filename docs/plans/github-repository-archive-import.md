# Import GitHub repositories as one archive

Status: draft

## Scope

Implement the import half of
[ADR 0009](../adr/0009-speed-up-github-canvas-transfers.md) and the
[draft specification](../specs/github-transfer-performance.md).
Keep this separate from [commit blob reuse](github-commit-blob-reuse.md).
No per-file fallback, intermediary service, new dependency, or change to
timeouts, retries, local persistence, or the import dialog.

## 1. Verify the browser transport

Use a minimal probe based on `main`, in the real Elseplane browser with an
existing GitHub App session for a disposable private fixture. Use the
existing default-branch head lookup and request
`GET /repos/{owner}/{repo}/zipball/{commitSha}`. Verify the HTTPS redirect
and cross-origin fetch with the actual browser client, not just `gh` or
`curl`. Use the GitHub API token only for `api.github.com`; never forward it
to the archive host or log the signed redirect URL. Require the expected
final HTTPS GitHub archive host. Inspect the browser client's streamed
response URL before reading its body; the current bounded-response helper
discards that URL after reading. Verify both that the browser strips the
API bearer on the cross-origin hop and that the private ZIP completes
within the existing timeout and body size limits. A final URL check alone
does not prove the bearer was stripped.

Validate the returned archive with the existing ZIP reader. Verify that its
exported canvas and attachment files give the expected import on the
fixture. This is a compatibility check, not a timing comparison.
If access, redirect safety, bounds, or ZIP compatibility cannot be
verified, stop and report the exact blocker before implementation. Do not
switch transports or relax validation.

## 2. Implement the archive source

1. `lib/github/github_api.dart` keeps destination verification and calls
   `_branchHead` directly for the archive request, not `_snapshot`. Import
   needs no commit metadata or recursive tree; commit still does. Use the
   redirect behavior proven above and the existing bounded request
   machinery. Reject a missing or unexpected final URL before reading its
   body. Remove the per-file GitHub blob-read path once its caller is
   replaced; do not change commit transport.
2. Use the library's `ZipTransferSource` for ZIP integrity and byte
   validation. In `lib/github/`, require a single common archive wrapper
   directory and strip exactly that segment. Pass root-relative entries
   and archive bytes through the existing transfer validation, including
   path and attachment checks after removing the wrapper. Do not add a
   tree reconciliation step. Unrelated files are ignored by the shared
   import decoder. Retain the existing GitHub-only 100 MiB per-file limit
   for regular entries, checked from declared sizes before decompression;
   keep the stricter 10 MiB image limit and the 140 MiB ZIP and aggregate
   limits. Do not change the limits for local ZIP imports.
3. Return the validated GitHub `TransferSource` to the existing workspace
   and shared decoder. Do not add a concurrency setting or change local
   ZIP handling. Preserve the current-attempt checks before and after
   awaited work and before returning the candidate. Keep cancellation
   immediate, with no local writes until the same confirmation and save.
4. Update the accepted [transfer contract](../specs/folder-based-canvas-transfers.md#github-checkpoints)
   and [architecture design](../arch/folder-based-canvas-transfers-design.md)
   before shipping so they describe archive-only import rather than
   recursive-tree and blob reads.

## Verification

- Extend `test/github/github_transfer_test.dart` to assert the pinned ZIP
  request, no commit-metadata, tree, or blob GETs, and equivalent root and
  nested paths.
  Cover an invalid wrapper, unsafe paths, an unexpected final HTTPS host
  rejected before body consumption, and a failed download.
  Keep ZIP integrity and size-limit coverage, including an entry above the
  GitHub per-file limit but below the aggregate limit.
- In `test/app/github_workspace_test.dart`, cover cancel during download,
  ignored late completion during a new attempt, unchanged confirmation and
  save, an export that omits a canvas without deleting its local copy, and
  no local writes after a failed archive. If an exported canvas refers to
  an omitted image, preserve the reference without fetching the image or
  deleting any existing local attachment.
- Run focused Chrome tests, `flutter analyze`, `flutter build web`, and
  the full Chrome suite before committing implementation.
- Verify the implemented flow on the private fixture through confirmation
  and save. Confirm one archive download with no per-file reads. No
  baseline run or timing comparison is required.
