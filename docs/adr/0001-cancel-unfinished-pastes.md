# Cancel unfinished pastes when their context ends

Status: accepted

Date: 2026-10-21

## Context

Clipboard reads, image decoding, and attachment writes can finish after the user leaves their target. Preserving these operations across navigation requires waiting for work, retaining selections, and coordinating controller lifetimes. It can delay navigation indefinitely and still miss individual input fields.

## Decision

An unfinished paste belongs to its original logical input context. Code source and title are separate contexts. Selecting another field or object, explicitly ending editing, changing tools (including tool-only undo or redo), opening an app dialog or file picker, document undo or redo, replacement, removal, and disposal cancel affected unfinished pastes and image uploads. Returning to the same field does not revive canceled work.

Temporary browser focus loss, clipboard permission prompts, and the device image picker do not end the logical context. Ordinary typing, caret movement, and transforms that keep the same editor open preserve it. A completed read applies to the live selection in that context.

Navigation cancels outstanding work and saves completed edits through the normal persistence queue. It never waits for clipboard reads or image uploads. A failed save preserves completed content for retry; canceled work remains canceled.

Cancellation prevents late document changes and stale error messages. A canceled Cut never deletes its original objects, although its system clipboard write may still finish. Attachment writes may also finish; cleanup attempts remove only new, unpublished paths. Current-context failures remain visible. Ordinary image display loading has a separate lifetime.

## Alternatives

Finishing every accepted paste before navigation requires a task registry, a blocking surface, retained selections, and handling for every input's controller lifetime. This approach is rejected because navigation must not depend on unfinished clipboard or image work.

Canceling on every focus-loss event would interrupt browser permission prompts and device image selection. Cancellation follows logical application transitions instead.

## Consequences

Users who leave a context before an operation completes may need to paste or select an image again. Completed edits remain saved normally. Generation checks prevent canceled work from applying later; no clipboard service or persistence-format change is required.
