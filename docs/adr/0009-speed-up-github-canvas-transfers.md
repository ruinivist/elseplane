# Speed up GitHub canvas transfers

Status: proposed

Date: 2026-11-24

## Context

A full headed-browser debug import of `elseplane-notes` spent 76.4 of 81.9
seconds downloading 43 blobs serially. A byte-identical copy of `web links`
took 67.4 seconds to commit, 58.2 of them uploading 32 blobs that the remote
tree already contained. These are historical observations, not release
timings or estimates of the gains below.

## Decision

**Reuse blobs from the commit's fresh target tree.** After destination and
output-path validation, compute the Git blob ID for each packaged file. If
that ID belongs to a regular blob in the captured tree, use it in the new
tree entry without uploading bytes. A match can come from a different path.
Otherwise upload the file as before. Build one tree and one commit on the
captured head, then update the selected default branch without force. This
does not change which bytes or paths the commit represents.

**Read up to eight distinct GitHub blobs in parallel.** Keep the captured
default-branch commit and its bounded recursive tree as the import
manifest. Request raw bytes by immutable blob ID directly from GitHub.
Fetch a blob only once per attempt, even when several paths refer to it.
Keep the shared decode, confirmation, and save flow. Local file imports
remain sequential.

GitHub owns authentication, snapshot selection, raw blob retrieval, and
deduplication within an attempt. The shared transfer codec schedules reads
and accounts for bytes; Workspace opts GitHub into the eight-read limit.
First verify private raw blob access in the actual browser with the
existing GitHub App session. If it fails, stop and report the blocker. Do
not add a transport fallback, durable cache, or dependency. The mediator
continues to handle tokens only, not file traffic.

**Report rate limits without shared cooldown state.** Stop the active
operation and show GitHub's wait hint, or advise waiting a minute. Do not
retry automatically or prevent the user from initiating another operation.
This removes shared mutable state that concurrent or stale responses
could otherwise update.

## Alternatives

- **Parallel uploads:** Speeds up necessary writes but still sends the
  unchanged images. Reuse first; measure the remaining uploads before
  considering concurrency.
- **One repository archive:** The private ZIP was available outside the
  browser, but the direct browser probe failed before receiving a usable
  response. Public archive responses allowed GitHub's render origin, not
  the app's origin. A relay would send all archive traffic through the
  mediator, which is outside its role.
- **Shallow Git clone:** GitHub's Smart HTTP endpoint did not grant CORS
  access to the app's origin in the public check. A browser Git client
  would not remove that restriction.

## Consequences

Commit trades local hashing for fewer round trips and less upload traffic.
Import overlaps network waits and avoids JSON/Base64 overhead. Each
distinct supported blob still costs one request. Eight is a ceiling, not a
speedup guarantee: total bytes, browser connection limits, and GitHub
rate limits still matter. Keep all existing path and byte limits and do not
change timeouts or retry policy.

The [draft behavior](../specs/github-transfer-performance.md) adds to the
accepted transfer contracts. The [commit](../plans/github-commit-blob-reuse.md)
and [import](../plans/github-parallel-blob-import.md) plans define the
work and checks separately.
