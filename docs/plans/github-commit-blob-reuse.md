# Reuse GitHub commit blobs

Status: draft

## Scope

Implement the commit half of [ADR 0009](../adr/0009-speed-up-github-canvas-transfers.md)
and the [draft specification](../specs/github-transfer-performance.md) first.
This does not depend on [repository archive import](github-repository-archive-import.md).
Make the production change on `main`.
Do not change the sync UX, local persistence, or write retry policy.

## Implementation

1. In `lib/github/github_api.dart`, retain authorization, the fresh snapshot,
   and all output-path validation before remote writes. After validation,
   index the normalized IDs of regular blobs in the captured tree, including
   paths outside the canvas's folder. Do not use the local baseline or an
   earlier snapshot as proof of remote bytes.
2. In the existing sorted path order, compute each packaged file's Git blob
   ID with the installed `crypto` package: SHA-1 over `blob <byte length>\0`
   followed by the exact file bytes. Feed the header and body as chunks
   rather than copying them into one full-size buffer. Keep the helper
   private to the GitHub commit code.
3. Use the ID directly on a match. On a miss, use the current blob POST and
   its returned ID. Keep all output entries, the base tree and parent, and
   the single non-forced ref update. Do not fetch remote blob bodies for
   comparison. Leave `GitHubSync` snapshot capture, notifications, and
   confirmed-baseline publication unchanged.

## Verification

- Extend `test/github/github_transfer_test.dart` for mixed reuse and upload,
  cross-path reuse with no blob POST, a known Git blob ID vector, and a
  same-length modified file. Assert the complete tree mapping and
  `force: false`; retain permission, collision, and uncertain-update tests.
- Run focused Chrome tests, `flutter analyze`, `flutter build web`, and the
  full Chrome suite before committing implementation.
- Verify the changed workflow on a disposable GitHub App fixture through
  the normal app flow. A new-path exact copy should make zero blob POSTs;
  a text edit whose new bytes are not already in the target tree and whose
  attachments are unchanged should make one. Check the resulting tree
  and changed paths on the fixture's selected default branch. No baseline
  run or timing comparison is required.
