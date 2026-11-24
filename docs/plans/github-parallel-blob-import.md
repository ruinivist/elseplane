# Overlap GitHub import blob reads

Status: draft

## Scope

Implement the import half of
[ADR 0009](../adr/0009-speed-up-github-canvas-transfers.md) and the
[draft specification](../specs/github-transfer-performance.md) on `main`.
Do not change how Commit publishes, local imports, persistence, the import
dialog, the mediator, timeouts, or retries. Simplify shared rate-limit
reporting across GitHub operations. No fallback transport or dependency.

## 1. Verify private raw blob access

Use a minimal read-only probe in the actual Elseplane browser with its
existing GitHub App session and a private fixture. Capture a validated
default-branch tree and choose a known canvas blob and a binary attachment
blob by their IDs. Request each from `api.github.com` using
`Accept: application/vnd.github.raw+json`. Check success without redirects,
body byte counts against the tree, and computed Git blob IDs against the
requested IDs. Use existing timeouts and response bounds. If private raw
reads fail, stop and report the cause before implementation; do not
fall back to Base64 or the archive. No fresh timing baseline is required.

The browser probe passed: one private canvas and one binary attachment
returned HTTP 200, with exact declared sizes and matching Git blob IDs.
This proves access, not full-import behavior or concurrency.

## 2. Implement bounded reads

1. **GitHub transport:** In `lib/github/github_api.dart`, keep destination
   verification, `_snapshot`, and `_transferEntries` so all repository
   paths and declared sizes are validated before blob reads. Change only
   import blob requests to use the proven raw response format, with no
   redirects. Classify non-success responses from status and headers
   without reading the body. Cancel the unread stream without letting a
   cleanup failure replace the HTTP error or escape as an unhandled error.
   Cap successful bodies at the declared blob size, then verify the exact
   length and Git blob ID using the existing private Git hash helper. Keep the
   100 MiB blob, 10 MiB attachment, and 140 MiB aggregate limits. Remove
   the old Base64 response decoding and bounds code if no callers remain.
2. **Attempt-local deduplication:** In `_transferEntries`, check that all
   paths declaring a normalized blob ID agree on size, while enforcing
   each path's limits. Reject inconsistent metadata before any blob GET.
   Then share one immutable read future per normalized ID in the GitHub
   source. A retry initiated by the user starts with a new source and no
   reused reads. Expose the same literal `TransferEntry` list.
3. **Scheduling:** Give `decodeTransfer` an optional read limit defaulting
   to one and an optional attempt-current callback. In
   `Workspace._prepareGitHubImport`, pass eight and the existing `isCurrent`.
   Keep local call sites sequential. After manifest validation, drain the
   existing sorted paths with at most eight read slots; don't create a
   future for every path up front. Count each literal path in the byte
   budget, store results by path, and retain existing deterministic decode
   and preview behavior.
4. **Failure and cancellation:** Check the attempt before claiming work
   and after awaited reads. On the first terminal error, stop scheduling
   and return the error without waiting for slower reads; observe every
   already-started future so later errors are handled. Retain
   `GitHubSync`'s immediate dismissal. Use a preparation-current predicate
   for scheduling and requests: the attempt must still own the dialog
   and be in Preparing. Keep the dialog identity check for showing results
   and dismissal. Ignore responses from ended attempts. No partial import
   or local writes before confirmation.
5. **Rate limits:** Remove the shared `_retryAt` cooldown and its
   pre-request checks, including for mediator calls. Preserve `429` and
   explicitly rate-limited `403` classification. Report GitHub's wait time
   from the existing headers, or advise waiting a minute when unavailable.
   Do not automatically retry or block a later user-initiated operation.
6. Update the accepted
   [transfer contract](../specs/folder-based-canvas-transfers.md#github-checkpoints)
   and [architecture design](../arch/folder-based-canvas-transfers-design.md)
   before shipping to describe bounded raw reads and attempt-local reuse.

## Verification

- In `test/github/github_transfer_test.dart`, assert the raw request and
  one GET per shared blob ID and distinct output paths. Reject inconsistent
  metadata without any blob GETs. Reject oversized successful bodies,
  short reads, and same-size wrong-content responses. A nonempty `429`
  response for a zero-byte blob must report rate limiting without reading
  the error body, even when stream cancellation throws. Retain
  authorization and snapshot validation checks.
- In `test/github/github_api_test.dart`, verify rate-limit advice and
  that a later explicit request reaches GitHub instead of being rejected
  by the client. Assert an ordinary permission-denied `403` stays distinct.
- In `test/library/transfer/canvas_transfer_test.dart`, use controlled
  completions to verify default sequential reads, the eight-read maximum,
  deterministic output, per-path accounting, and stopping on failure.
  In `test/app/github_workspace_test.dart`, verify cancellation with reads
  pending, a terminal failure shown without waiting for a sibling, and a
  new attempt unaffected by a late sibling `429` after the failure.
  Verify unchanged confirmation and save behavior.
- Verify the normal successful import on a private fixture and check
  request counts and peak in-flight reads without logging private content
  or credentials. No before-and-after timing requirement.
- Run focused Chrome tests, `flutter analyze`, `flutter build web`, and
  the full Chrome suite before committing implementation.
