# Known bugs

These behavior fixes are deferred from the stage 3 architecture migration.

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

Status: open.

Location: `lib/canvas/editor/canvas_page.dart`, `_handleSelectableElementPointerDown`, `_handleCanvasPointerDown`, and `_copySelection`.

To reproduce:

1. Select shape A with no active editor.
2. Start Cut while the clipboard write is delayed.
3. Drag an unselected, inactive shape B and release it.
4. Let the clipboard write finish.

Expected: the change of object context cancels Cut and leaves A intact, following the [paste cancellation decision](adr/0001-cancel-unfinished-pastes.md). Actual: A is deleted after B has moved.

Pressing B clears selection, but `_setActiveElement(null)` returns early when no object is active. The pending clipboard generation remains valid, so the completed Cut still deletes its captured objects.

Fix: invalidate pending canvas clipboard work when pressing a different object changes the input context, before clearing selection. Preserve transforms within the same open editor. Add a delayed-Cut regression covering a completed drag of an unselected object.
