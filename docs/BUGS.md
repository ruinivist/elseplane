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

Expected: the editor returns to the same content and scroll position. Actual: wrapped-line layout changes the restored position; the [resource culling regression test](../test/canvas/editor/element_resources_test.dart) reproduces an offset changing from 120 to 260 even though the scroll controller retains its offset.

Fix: add correct wrapped-code scroll restoration in `re_editor`. Its public API does not provide a scroll snapshot/restore contract. Leave stage 5 pending until a library fix is available; the dependency remains unchanged.

## 4. Corrupt image bytes pass validation on web

Status: open. Image validation bug affecting paste, import, and restore.

Location: [attachment validation](../lib/attachments/image_import.dart), `validateCanvasAttachment`; [text image paste](../lib/canvas/editor/elements/text/text_markdown_editor.dart), `TextClipboardEdits.insertPastedImage`.

To reproduce, create a project containing a Markdown image reference to a valid attachment path, with `[1, 2, 3]` as that attachment's bytes. Import the project on web. Pasting those bytes through `insertPastedImage` also saves them as a PNG attachment.

Expected: reject corrupt image data before writing attachments or publishing document changes. Actual: the corrupt attachment is accepted; project export/reimport and library backup also succeed with those bytes.

`ImageDescriptor.encoded` only wraps bytes on Flutter web; creating a descriptor does not decode or validate the image. Text image paste checks only byte length before writing. The malformed-image case in [the project tests](../test/library/transfer/canvas_project_test.dart) has no matching document reference, so attachment-map validation rejects it before image validation runs.

Fix: make the shared validator decode the image using the existing `readCanvasImageSize`, and call that validator before text-image writes. Preserve cancellation checks and cleanup. Test corrupt bytes with a genuine document reference so the image validator is exercised.

## 5. Markdown attachment images reload after culling

Status: open. Rendering resource ownership gap in refactor stage 5.

Location: [Markdown preview](../lib/canvas/editor/elements/text/text_markdown_preview.dart), `_buildImage`; [retained text resources](../lib/canvas/editor/elements/text/text_editor_resources.dart).

To reproduce:

1. Display a text block containing an attachment image using a store that counts reads.
2. Wait for the image to load.
3. Pan until the text block is culled, then pan back.

Expected: the unchanged image and its load survive with the retained element resources. Actual: the same `TextEditorResources` instance survives, but attachment reads increase from 1 to 2. With delayed reads, the returning image must wait for storage again.

`_buildImage` starts a new `attachmentStore.read(path)` during widget construction. Inline image loads remain owned by the culled widget instead of retained element resources, contrary to the architecture's resource lifetime rule.

Fix: retain source-keyed inline image loads and image resources with `TextEditorResources`, pass them to the preview, and retire them when the source or element lifetime ends. Add culling and restoration coverage for Markdown images alongside media images.

## 6. Oversized canvas image pastes fail silently

Status: open. Current-context error reporting bug.

Location: [canvas clipboard workflow](../lib/canvas/editor/canvas_clipboard.dart), `CanvasClipboard.paste`.

To reproduce, paste an image larger than 10 MiB onto the canvas while remaining in the same input context.

Expected: report the rejected paste, following the [paste cancellation decision](adr/0001-cancel-unfinished-pastes.md). Actual: nothing is inserted and no error appears. `readCanvasClipboard` throws `FormatException` for the size limit, but the nested catch in `paste` returns silently before the normal error handler runs.

Fix: remove the nested `FormatException` catch and use the existing outer handler, which reports current-context failures and suppresses canceled ones. Cover oversized current and canceled pastes separately.

## 7. Five tests still use superseded element lifecycles

Status: open. Test migration failures; no production behavior bug confirmed in these cases.

Location: [group document batching tests](../test/canvas/editor/canvas_document_batch_test.dart) and [font tests](../test/theme/fonts_test.dart).

To reproduce, run these files in Chrome:

```sh
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome test/canvas/editor/canvas_document_batch_test.dart test/theme/fonts_test.dart
```

Expected: the migrated tests exercise the current input and document lifecycles. Actual: four group-move cases (100/1000 elements, Auto off/on) and the font case `ignores completion after block is deleted` fail.

The group tests call `PenElementView.onMove` without starting a pointer sequence. `CanvasInputTarget` correctly rejects those unarmed callbacks. The font test disposes rendering resources while leaving the session element active; the settings panel now consumes the session and element ID, so this does not represent deletion.

Fix: start and drain a real pointer around the group batching callbacks, and remove the font target through `EditorSession.remove`. Temporary probes using those lifecycles passed all five existing assertions. Keep the production lifetime guards and migrate the fixtures.

## 8. Completed pen drags merge with the next action

Status: open. Undo grouping regression.

Location: [canvas projection](../lib/canvas/editor/canvas_view.dart), `_buildElement`; [pointer handling](../lib/canvas/editor/canvas_input.dart), `CanvasInput.pointerUp`.

To reproduce:

1. Drag a pen stroke with Auto off and release it.
2. Right-click another object with Auto on and another object above it in the saved stack.
3. Undo.

Expected: Undo reverses the right-click's layer promotion and leaves the completed stroke movement intact. Actual: it also returns the stroke to its original position.

`CanvasInput.pointerUp` leaves transformed object operations for recognizer callbacks to finish. `PenElementView` exposes `onChangeEnd`, but `_buildElement` does not supply it, so the drag remains part of the next operation.

Fix: pass `onChangeEnd: target.finish` to `PenElementView`, matching the other draggable views. Add a regression test covering a completed stroke drag followed by another object's layer promotion.

## 9. Separate object clicks merge their layer promotions

Status: open. Undo grouping regression.

Location: [pointer handling](../lib/canvas/editor/canvas_input.dart), `CanvasInput.pointerUp` and `CanvasInputTarget.activate`.

To reproduce:

1. Create three Auto-on shapes A, B, and C in that back-to-front order.
2. Click A. The saved order becomes B, C, A.
3. Right-click B. The saved order becomes C, A, B.
4. Undo.

Expected: the saved order returns to B, C, A, preserving the first click's promotion. Actual: it returns to A, B, C, undoing both clicks together.

`CanvasInput.pointerUp` finishes a non-transforming object operation before the tap recognizer calls `activate` and promotes the object. That promotion remains unfinished and merges with the next right-click's promotion.

Fix: finish non-editing click operations after their tap callbacks run. Preserve typing groups in focused editors and add a regression test for consecutive promotions through primary and secondary clicks.
