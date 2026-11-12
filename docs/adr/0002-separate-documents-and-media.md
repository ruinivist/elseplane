# Store canvas documents separately from media

Status: accepted; transfer and replacement-import portions superseded by ADR 0005

Date: 2026-11-05

The transfer-format and replacement-import decisions below were superseded by
accepted [ADR 0005](0005-folder-based-canvas-transfers.md) on 2026-11-11. This
ADR remains authoritative for separating document JSON from media bytes,
canvas-relative references, rejecting base64 canvas documents, and its
trust-boundary validation rationale.

## Context

A canvas contains structured values and may reference local image bytes. A
single-canvas transfer needs to preserve both without turning binary data into a
second canvas value format or tying the archive to one storage provider.

## Decision

Canvas values are JSON. Media stays in separate, byte-identical files at
canvas-relative `attachments/<uuid>.<extension>` paths. These are the portable
document and single-canvas archive paths. The accepted [attachment storage
decision](0006-path-aware-attachment-store.md) distinguishes them from full
root-relative storage keys. At this ADR's original baseline callers used
root-level keys; parent-aware adoption was later accepted by ADR 0005 and is
implemented. The portable document reference remains canvas-relative.

A single-canvas download is `canvas.elseplane.zip` with the `application/zip`
media type. The ZIP is a transport container, not a conceptual canvas document
format. It contains `document.json`, which is the existing versioned
`CanvasDocument` JSON written directly and pretty-printed, plus each referenced
local image once at `attachments/<uuid>.png`, `.jpg`, `.gif`, or `.webp`.
External image URLs remain external and are not copied into the archive. Canvas
archive import and export do not support legacy base64 JSON. The whole-library
ZIP layout does not change.

Before expanding entries, validate the archive's allowed entries and declared
sizes, and reject duplicates, unsafe paths, and symlinks. After expansion,
verify actual sizes and checksums, then validate the document, image bytes, and
attachment references.
The compressed archive and total uncompressed content are each limited to
140 MiB; each image is limited to 10 MiB.

Import keeps the staged replacement protocol: confirm before replacing, stage
attachments at fresh unused paths, remap document references, then publish.
Cancellation or failure leaves existing content and attachment bytes intact.
Future storage providers may read or write the same logical files directly; no
provider work is part of this decision.

## Alternatives

Embedding image bytes as base64 in canvas JSON is rejected because it mixes
binary media with document values and preserves a second JSON transfer format.
Treating the ZIP itself as the canvas document format is also rejected; ZIP
serves only as the downloadable container. Defining a separate archive layout
for each storage provider would make transfers depend on the provider.

## Consequences

The original canvas-transfer format, attachment-staging workflow, and unchanged
whole-library archive consequence are superseded by ADR 0005 and its accepted
specification. The enduring consequences are that base64 JSON canvas transfers
are unsupported, document and media bytes remain separate, and a transfer
container does not promise streaming or lower memory use.

## Superseded by

[ADR 0005](0005-folder-based-canvas-transfers.md) supersedes only this ADR's
transfer-layout and replacement-import portions. It does not supersede the
document/media separation or validation rationale above.
