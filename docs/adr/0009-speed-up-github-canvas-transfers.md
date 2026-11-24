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

**Import one GitHub repository ZIP pinned to the captured commit.** Treat it
as the exported snapshot: the ZIP determines both the file list and the
bytes to import. Do not fetch a separate recursive tree or individual blobs
for import. Validate the archive and keep the existing shared decode,
confirmation, and save flow. Local file imports do not change.

GitHub continues to own authentication, snapshot selection, and archive
retrieval. The library owns ZIP validation and the shared transfer codec.
Verify private archive access and ZIP compatibility in the browser before
implementing import. If that check fails, report the blocker and stop the
import task. Do not add a per-file fallback, durable cache, dependency, or
transport service.

## Alternatives

- **Parallel uploads:** Speeds up necessary writes but still sends the
  unchanged images. Reuse first; measure the remaining uploads before
  considering concurrency.
- **Concurrent blob reads:** Shorten the serial wait but still make a
  request per file. Not part of this design or a fallback.
- **Shallow Git clone:** Uses a bulk transfer too, but requires Git protocol
  support and packfile handling when we only need the files at one commit.

## Consequences

Commit trades local hashing for fewer round trips and less upload traffic.
Archive import replaces per-file network round trips with one archive
download. It also downloads unrelated files and shifts work to ZIP
validation and decompression. Honor omissions from archive export rules
such as `export-ignore`; do not fetch excluded files separately or treat
their absence as an error. Exported bytes still have to pass the normal
import checks. We no longer guarantee that an export includes every tracked
file or matches the raw blob bytes when export rules rewrite a file. Verify
the request-count reduction without assuming a wall-time gain. Do not
change timeouts or retry policy.

The [draft behavior](../specs/github-transfer-performance.md) adds to the
accepted transfer contracts. The [commit](../plans/github-commit-blob-reuse.md)
and [import](../plans/github-repository-archive-import.md) plans define the
work and checks separately.
