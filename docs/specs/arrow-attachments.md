# Arrow attachments

Status: accepted. Extends the [existing arrow behavior](interaction-model.md#arrows).

## Scope

Either endpoint of an arrow can attach to a shape, text block, code block, or media block (image, link card, or unresolved media). Freehand strokes and other arrows are not attachment targets. An arrow can have zero, one, or two attached endpoints. Existing arrows stay free until edited; nothing attaches just because an arrow and a block happen to touch.

## Behavior

- Start or finish drawing over a block body, or near one of its attachment points, to snap that endpoint. On an existing arrow, activate it and drag the start or tip to attach it, move it to another point, or detach it by releasing away from an eligible target. Dragging a curve handle never attaches an endpoint.
- Each block has four attachment points: the middle of the top, right, bottom, and left sides in the block's own orientation. For nonrectangular shapes, use the outline in those four directions from the shape's center. Code attaches to the body, not the title tab; media attaches to the body or its unresolved placeholder, not to floating controls.
- Snap to the closest eligible attachment point across all blocks, measured in logical screen pixels. All four points on a block qualify when the pointer is inside its body; otherwise only points within 12 pixels qualify. The frontmost block wins a distance tie. A nearby point on another block can win even when the pointer is over a block body. While snapping, show a small hollow accent ring centered on the winning point, about 12 logical pixels wide at every zoom, and snap the preview to it. The ring disappears when there is no candidate or the gesture ends. If the pointer and geometry have not changed, release uses the point shown in the preview. Canceling an endpoint drag discards the preview and leaves the connection, geometry, and undo history unchanged.
- A connected endpoint follows its chosen point as the block moves, resizes, rotates where supported, or changes its displayed size. It does not switch sides on its own. Connections still work when the target scrolls out of view. If the final size is not known yet, use the block's current layout estimate, then follow the measured edge once available.
- Moving a block does not move the arrow's free endpoint or curve handles. Dragging the arrow body moves its free endpoints and curve handles, leaving its bound endpoints attached. Moving a selected group that includes an arrow and both targets translates the whole arrow exactly once. A block moving on its own does not promote its connected arrows in the stack.
- Deleting, erasing, or cutting a block leaves surviving arrows in place, with the affected endpoints free at their last displayed positions. Undo restores the block and connections in one step; redo removes them again. An explicit arrow endpoint edit is one undoable operation. Loading an image or measuring text never adds an undo step or dirties the document by itself.
- Copy and paste keep a connection only if the arrow and that endpoint's target were both copied. It then connects to the pasted copy of the target, never to the original. Other endpoints paste as free points. Saving, reopening, and transferring a whole canvas preserve its connections.
- Keep existing arrow styling, drawing controls, curve editing, and one-shot Arrow tool behavior. Right-clicking while drawing still pins a Bézier control at the cursor, even when the tip is snapped. Those controls are never attachment points.
- Moving blocks together can make endpoints coincide without breaking either connection. Keep the existing handle order: when the handles fully overlap, the tip is on top and dragging it edits only that endpoint. Move a block or drag the tip away to expose the start handle. There is no special handle picker or cycling gesture.

## Acceptance criteria

- Draw a diagram with several arrows attached to the same block. Move or resize the block: all connected tips stay on the selected sides. Rotate a text, code, or resolved media block: its connection rotates with it.
- Reattach one tip and detach the other without changing the curve handles. Cancel a later drag: geometry, connection, and undo history stay unchanged.
- Drag an arrow alone, then move it with both targets selected: attached endpoints stay pinned in the first case; the whole diagram moves without drift in the second.
- Delete a target and undo the deletion; copy an arrow alone, then with one or both targets; reopen the saved canvas. Verify the relationships in each case.
- Verify snap feedback at multiple zoom levels, including a closer point on a neighboring block and a distance tie between overlapping blocks. Check that release matches the preview and right-click pins a control at the cursor, not on the snapped tip. Verify a nonrectangular shape and a target whose size changes after the arrow is drawn. Strokes and arrows never offer attachment points.
- Bring connected endpoints together and verify both bindings survive. Drag the visible tip away and verify the start is unchanged.

## Non-goals

Automatic side switching, obstacle avoidance, custom attachment points, connections to strokes or arrows, cross-canvas connections, and a new touch editing workflow.
