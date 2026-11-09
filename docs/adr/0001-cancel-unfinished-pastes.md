# Do not coordinate asynchronous edits across contexts

Status: accepted

Date: 2026-11-09

## Context

Clipboard reads, image decoding, and attachment writes can finish after the
user changes fields, selection, tools, or document history. Generation-based
cancellation requires extra state and invalidation plumbing across input,
focus, editor, and navigation owners. Waiting for every operation would instead
make navigation depend on work outside the persistence queue.

## Decision

Do not coordinate pending clipboard or device-image work across logical
context changes. An accepted operation may finish after field, selection,
activation, tool, or undo/redo changes. Field pastes use the target's live
selection; canvas pastes keep their captured destination, and Cut uses its
captured targets after a successful clipboard write while the original session
is live.

Keep basic target safety: ignore completion when the editor session has ended
or the original element is removed, detached, or disposed. On failure or target
loss, clean up only newly written, unpublished attachment paths; never delete a
published path. Preserve existing validation and failure reporting.

Navigation saves completed edits through normal persistence and does not wait
for pending clipboard reads or uploads. Pending work has no completion or
persistence guarantee; a late edit is saved only by an ordinary later save.

## Alternatives

Canceling on field, selection, tool, dialog, or history changes is rejected:
it requires context generations and invalidation plumbing in otherwise
independent owners. Waiting for every operation is rejected because it can
delay navigation and requires a task registry and retained controller state.

## Consequences

Late completion may modify the original surviving target or live selection
after the user has changed context. A successful delayed Cut may remove its
captured targets if its original session remains live. Removed, disposed, or
replaced targets remain protected, and ordinary image and metadata loads keep
their separate source-keyed lifetimes.
