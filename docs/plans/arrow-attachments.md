# Implement arrow attachments

Status: active. Implementation is complete; broader manual verification remains open.

## Goal

Implement the [arrow attachment specification](../specs/arrow-attachments.md) within the existing [editor ownership](../arch/editor-lifecycles.md) and [persistence](../arch/persistence.md) boundaries. Keep the existing arrow tool and geometry; no routing engine, dependency changes, or input migration.

## Design

### Saved relationships

Extend `ArrowElementData` with optional `startAttachment` and `endAttachment` values, each containing a target element ID and a local side. The existing `start` and `end` fields remain canvas-space points: authoritative for free ends and fallbacks for attached ends. Record the resolved point when attaching; do not rewrite it every time the target moves or its layout updates. Control points stay in canvas coordinates.

Add the values to copying, equality, hashing, and generated JSON. Omit absent fields so existing free-arrow documents and clipboard payloads read unchanged and do not change their canonical encoding. Keep the current document and clipboard versions for these additive fields; reading new attachments in older app builds is not supported.

Keep the existing decoders and strict field validation. Share a document-layer relationship validator across decoded documents, decoded clipboard fragments, and the prospective document on session insertion. Build the ID map once, reject duplicate IDs, then validate references against the complete collection so forward references work. Reject missing or disallowed targets; never resolve links outside the collection. On an individual endpoint edit, apply the same target rule through the session's existing ID lookup before publishing, without rescanning the document.

Keep the minimum length for new arrows. Do not use a minimum endpoint distance as a saved-value invariant: two attached tips can converge when blocks move, and deleting or copying targets must be able to preserve the resulting points without nudging either tip. Keep finite coordinate, control-list, and stroke validation. Guard the existing minimum-length math against a coincident current endpoint when editing a free point.

### One geometry for drawing and interaction

Put anchor calculations in `lib/canvas/geometry`: resolve the four points in a supplied body frame, rotate around the same pivot as the grid, and use `shapePath` for nonrectangular outlines. Keep lookup and stacking in the editor. A code block's body frame uses its saved body rectangle and the grid's existing body-centered rotation; it excludes the title tab. A text block uses saved size where explicit and the grid's measured child size for natural height. Media uses `MediaResources.canvasSize`, including its placeholder until an image resolves. Use the existing declared size or last measured size when a target is culled; do not mount an offscreen widget to measure it.

`CanvasView` projects the saved arrow and its target frames to one effective `ArrowGeometry`. Use it for the grid child position and bounds, the painter, path hit testing, and the active arrow handles and guides. Test body containment in local coordinates; compare eligible anchors across blocks by screen distance. Break ties by saved order plus the active lift, then top, right, bottom, left within a block. Do not use the current `hitTest` iteration order. Use the same candidate rule for preview and release. Keep the existing handle stack order when endpoints coincide.

Refresh affected arrow projections after target geometry is synced for a document edit, and when an existing grid measurement or media size changes. Read retained sizes through the grid's `getInfo` and use its controller notifications for measured changes. Compare target frames or projected geometry before updating the grid so viewport notifications and the arrow's own size update cannot cause a feedback loop. Reuse existing view/session lifetimes; do not save measurements or add an arrow resource or connector registry. Verify that the existing grid notifications suffice for natural-height text and media changes.

### Input and document edits

- `CanvasInput` gives `ArrowTool` access to live anchor resolution for accepted gestures, including primary release detected while the secondary button is still held. Keep the chosen start side fixed but resolve its current position for preview and release. Resolve the moving tip from the last pointer sample through the current viewport. Use the snapped positions for the preview and default bend, but keep secondary-pinned control points at the unsnapped cursor. Clear the draft before the placement callback, and let `EditorSession.insert` own the existing placement history and return to Select.
- Keep active endpoint drags as transient view state. Store the last pointer in screen coordinates so panning or zooming resamples the anchor under the cursor. The painter, handles, and hollow ring use the same projected draft; the ring has no pointer hit area. Split the current shared pan-end and pan-cancel path for endpoints. On release, recheck the candidate and live target, then ask `EditorSession` to set or clear the attachment and save the endpoint in one edit. On cancellation, deactivation, tool change, or document replacement, discard the draft without publishing an edit or changing undo or redo. Keep control-point edits on their current path.
- Apply body and group translation in `EditorSession.move`; translate controls and free endpoints for explicitly moved arrows, and derive bound endpoints from the targets after the move. Do not propagate promotion or issue a second edit for dependent arrows.
- Pass one unbracketed `CanvasView` removal callback to `CanvasInput` and `CanvasClipboard` and use it for Delete as well. It captures affected resolved endpoints before removing any targets and passes those points to `EditorSession.remove`. The session frees only the affected ends of surviving arrows in the same snapshot that removes the targets; it does not query the view or grid. Keep each caller's history boundaries, including one operation for a whole eraser sweep. Keep Cut's successful-write and target-lifetime checks; use current geometry at removal time, not the geometry at clipboard-write time.
- `CanvasClipboard` captures the current resolved endpoints at copy time and strips references to targets outside the fragment before encoding. On paste, validate the fragment before attachment I/O, assign new IDs in two passes, and remap attachment references only within the fragment. Use the captured geometry for placement bounds. Apply the paste offset once to block positions, control points, and stored endpoint coordinates; projected attached ends use the new targets. Keep the existing one-step Paste and selection behavior.

## Sequence

1. Add saved attachment values, validation, and pure anchor math. Regenerate `canvas_document.g.dart` with the existing `build_runner`. Cover legacy free arrows, valid references in either order, invalid references, and shape/rotation geometry.
2. Thread effective arrow geometry through `CanvasView` and the arrow painter and editor. Verify bounds and hit testing update for moves, transforms, delayed image sizing, and natural-height text, including when a target is culled.
3. Add snapping to creation and endpoint editing. Wire movement, removal, and clipboard behavior through the existing session and history operations. Extend the accepted interaction model's Arrows section to link the feature spec when its behavior is accepted.
4. Run focused checks and a web smoke test, then run the implementation review. Mark the plan complete only after verification; archive it and keep the accepted behavior spec.

## Verification

Focused Chrome tests cover the document codec, clipboard, session history, snapping, and connector geometry, including delayed image loading while the target is offscreen. The checks below also describe the broader manual scenarios; the large-canvas performance check is still open.

- Run focused Chrome tests with `CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome`. Extend `canvas_document_test.dart`, `arrow_geometry_test.dart`, `editor_session_test.dart`, `arrow_tool_test.dart`, `arrow_element_test.dart`, `canvas_input_test.dart`, and `canvas_clipboard_test.dart` at their respective boundaries. Cover both successful relationships and the cases where a relationship must not be created or preserved. Include save/reload via the shared document codec.
- Verify that a rejected endpoint edit publishes nothing and an invalid clipboard fragment starts no attachment I/O. Verify that one Undo restores all targets and bindings removed in an eraser sweep, a failed Cut removes nothing, and a target moved while Cut waits detaches at its removal-time position. After previewing another anchor, test release and cancellation separately, including preservation of redo on cancel.
- Verify the creation preview and committed bend use live anchor geometry after a target changes size. Pan with the wheel during a stationary endpoint drag and verify both feedback and release use the new viewport.
- Run `flutter analyze` and `flutter build web`.
- In the web app, draw a shape-to-text-to-image diagram, move one block with several arrows, rotate a block, and change the content height of a text block. Check that a moved curve can be hit at its new location and not at its old one. Verify snap feedback under zoom, cancellation, undo after erasing a target, and copy/paste with and without targets. Move or resize blocks while a target is offscreen and check the visible portions of its arrows.
- Exercise a canvas with many unrelated blocks and several connectors on one target. Check for a repeated grid update after measurements settle or visible lag during a drag; use that evidence before adding any indexing or caching.
