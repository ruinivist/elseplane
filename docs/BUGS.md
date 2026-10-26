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

Location: `CanvasInputTarget.pointerDown` in [canvas input](../lib/canvas/editor/canvas_input.dart) invalidates the outgoing edit context; [CanvasClipboard](../lib/canvas/editor/canvas_clipboard.dart) checks its captured lifetime before deleting Cut targets. The [clipboard tests](../test/canvas/editor/canvas_clipboard_test.dart) cover a delayed Cut followed by a completed drag of another object.

## 3. Wrapped code scroll position changes after culling

Status: avoided by design. Code blocks hardcode wrapping off and scroll long lines horizontally, so this no longer blocks refactor stage 5. The upstream defect remains relevant if wrapping is ever enabled.

Location: `re_editor` 0.10.0 wrapped-line layout when a code editor remounts.

To reproduce:

1. Enable code wrapping in the implementation and create a code element with long, wrapped lines.
2. Scroll vertically within the code editor.
3. Pan the canvas until the element is culled, then pan back.

Expected: the editor returns to the same content and scroll position. Actual: wrapped-line layout changes the restored position. The former wrapped-code regression reproduced an offset changing from 120 to 260 even though the scroll controller retained its offset; that test was removed because wrapping is no longer supported.

Before enabling wrapping, fix wrapped-code scroll restoration in `re_editor`. Its public API does not provide a scroll snapshot/restore contract. A comment beside `wordWrap: false` records this constraint; the dependency remains unchanged.

## 4. Corrupt image bytes pass validation on web

Status: fixed. Shared attachment validation decodes the first image frame through `readCanvasImageSize`. Project import, library restore, and backup reject corrupt bytes. Markdown image paste validates before writing and rechecks the target lifetime afterward, preserving silent cancellation and write cleanup.

Location: [attachment validation](../lib/attachments/image_import.dart), `validateCanvasAttachment`; [text image paste](../lib/canvas/editor/elements/text/text_markdown_editor.dart), `TextClipboardEdits.insertPastedImage`.

The [attachment tests](../test/attachments/attachment_test.dart) cover rejection before any write or text/selection change, and cancellation during validation with valid and corrupt bytes. The [project regression](../test/library/transfer/canvas_project_test.dart) includes a genuine Markdown image reference so image decoding is exercised. The [archive tests](../test/library/transfer/canvas_library_archive_test.dart) reject corrupt referenced images during backup and restore.

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
