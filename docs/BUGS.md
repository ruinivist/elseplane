# Known bugs

Known behavior bugs and refactor blockers.

## 1. Attachment rebasing rewrites prose and code

Status: open.

Location: `lib/library/transfer/canvas_project.dart`, `rebaseCanvasDocumentAttachments`.

Import and restore assign fresh paths to imported attachments. Markdown rebasing uses `replaceAll` across the entire source, so it also changes matching paths in prose, inline code, and fenced code blocks.

To reproduce, import a canvas containing an image and a literal copy of its path:

```markdown
![image](attachments/00000000-0000-4000-8000-000000000000.png)

Original path: `attachments/00000000-0000-4000-8000-000000000000.png`
```

Expected: only the image destination changes. Actual: both occurrences change, silently altering saved text.

Fix: use parser-provided source ranges to rewrite actual image destinations. Deduplicate shared reference definitions and apply edits from right to left. Preserve prose, code, and surrounding Markdown formatting. Add a regression test for literal paths beside real images.

## 2. Dragging another object leaves delayed Cut alive

Status: fixed. Editor session context changes invalidate the pending Cut before dragging another object. A delayed-Cut regression covers the completed drag.

Location: `lib/canvas/editor/canvas_page.dart`, `_handleSelectableElementPointerDown`, `_handleCanvasPointerDown`, and `_copySelection`.

To reproduce:

1. Select shape A with no active editor.
2. Start Cut while the clipboard write is delayed.
3. Drag an unselected, inactive shape B and release it.
4. Let the clipboard write finish.

Expected: the change of object context cancels Cut and leaves A intact, following the [paste cancellation decision](adr/0001-cancel-unfinished-pastes.md). Actual: A is deleted after B has moved.

Pressing B clears selection, but `_setActiveElement(null)` returns early when no object is active. The pending clipboard generation remains valid, so the completed Cut still deletes its captured objects.

Fix: invalidate pending canvas clipboard work when pressing a different object changes the input context, before clearing selection. Preserve transforms within the same open editor. Add a delayed-Cut regression covering a completed drag of an unselected object.

## 3. Wrapped code scroll position changes after culling

Status: open. Blocks completion of refactor stage 5.

Location: `re_editor` 0.10.0 wrapped-line layout when a code editor remounts.

To reproduce:

1. Create a code element with long, wrapped lines.
2. Scroll vertically within the code editor.
3. Pan the canvas until the element is culled, then pan back.

Expected: the editor returns to the same content and scroll position. Actual: wrapped-line layout changes the restored position; the enabled, isolated `known re_editor defect: wrapped code retains its scroll offset after culling` [regression test](../test/canvas/editor/element_resources_test.dart) reproduces an offset changing from 120 to 260 even though the scroll controller retains its offset.

Fix: add correct wrapped-code scroll restoration in `re_editor`. Its public API does not provide a scroll snapshot/restore contract. Leave stage 5 pending until a library fix is available; the dependency remains unchanged.

## 4. Corrupt image bytes pass validation on web

Status: open. Image validation bug affecting paste, import, and restore.

Location: [attachment validation](../lib/attachments/image_import.dart), `validateCanvasAttachment`; [text image paste](../lib/canvas/editor/elements/text/text_markdown_editor.dart), `TextClipboardEdits.insertPastedImage`.

To reproduce, create a project containing a Markdown image reference to a valid attachment path, with `[1, 2, 3]` as that attachment's bytes. Import the project on web. Pasting those bytes through `insertPastedImage` also saves them as a PNG attachment.

Expected: reject corrupt image data before writing attachments or publishing document changes. Actual: the corrupt attachment is accepted; project export/reimport and library backup also succeed with those bytes.

`ImageDescriptor.encoded` only wraps bytes on Flutter web; creating a descriptor does not decode or validate the image. Text image paste checks only byte length before writing. The malformed-image case in [the project tests](../test/library/transfer/canvas_project_test.dart) has no matching document reference, so attachment-map validation rejects it before image validation runs.

Fix: make the shared validator decode the image using the existing `readCanvasImageSize`, and call that validator before text-image writes. Preserve cancellation checks and cleanup. Test corrupt bytes with a genuine document reference so the image validator is exercised.

## 5. Markdown attachment images reload after culling

Status: fixed. `TextEditorResources` owns lazy, source-keyed inline attachment and HTTPS image loads through `TextMarkdownImages`. Pending reads and decoded image streams survive culling, editing/preview transitions, and restoration with unchanged sources. Removed sources and detached element lifetimes invalidate pending completions immediately.

The [resource tests](../test/canvas/editor/element_resources_test.dart) cover duplicate/reference images, pending and completed loads across culling, decoded stream retention, source reconciliation, read failures, and stale completions after source changes, removal, or disposal. Markdown preview only renders retained snapshots; it no longer starts independent storage reads.

## 6. Oversized canvas image pastes fail silently

Status: open. Current-context error reporting bug.

Location: [canvas clipboard workflow](../lib/canvas/editor/canvas_clipboard.dart), `CanvasClipboard.paste`.

To reproduce, paste an image larger than 10 MiB onto the canvas while remaining in the same input context.

Expected: report the rejected paste, following the [paste cancellation decision](adr/0001-cancel-unfinished-pastes.md). Actual: nothing is inserted and no error appears. `readCanvasClipboard` throws `FormatException` for the size limit, but the nested catch in `paste` returns silently before the normal error handler runs.

Fix: remove the nested `FormatException` catch and use the existing outer handler, which reports current-context failures and suppresses canceled ones. Cover oversized current and canceled pastes separately.

## 7. Five tests still use superseded element lifecycles

Status: fixed. Group batching fixtures now arm a real pointer before delivering movement callbacks and cancel it afterward to drain recognizers without synthesizing a tap. Font deletion removes the target through `EditorSession.remove` and disposes rendering resources after consumers detach. Transform-layout fixtures likewise arm their controls before invoking callbacks.

The existing [batching](../test/canvas/editor/canvas_document_batch_test.dart) and [font](../test/theme/fonts_test.dart) assertions are retained. Production lifetime guards remain intact; input targets additionally bind transform completion to their originating gesture so an old completion cannot split a newer operation.

## 8. Completed pen drags merge with the next action

Status: fixed. CanvasView supplies `PenElementView.onChangeEnd` with its lifetime-bound target completion, matching the other draggable views.

The [history tests](../test/canvas/editor/canvas_history_test.dart) cover released and canceled stroke drags followed by another object's layer promotion. Undo reverses the promotion independently, and another Undo reverses the drag; Redo restores both operations in order.

## 9. Separate object clicks merge their layer promotions

Status: fixed. Raw object-pointer release leaves completion to the tap or drag callback. Non-editing activation and interaction callbacks finish after applying their Auto promotion; focused editors retain their logical content operation. A rejected pan recognizer no longer finishes an operation when no drag started.

The [input tests](../test/canvas/editor/canvas_input_test.dart) cover tap callbacks on either side of raw release and reject completions from older gesture bindings. The [history tests](../test/canvas/editor/canvas_history_test.dart) cover separate shape and pen taps followed by secondary-click promotions, with independent Undo steps.
