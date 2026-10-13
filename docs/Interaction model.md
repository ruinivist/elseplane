# Interaction Model

Text, code, and media blocks share three independent interaction states.

| State | Meaning | Behavior |
| --- | --- | --- |
| Inactive | A normal canvas object | Content is not editable. Clicking activates the block; dragging moves it without activating it. Options, transform controls, and resize handles are hidden. |
| Active | The primary object being worked on | Options and move, rotate, arrange, delete, and resize controls are available. |
| Selected | Part of the canvas selection | The block receives an accent highlight and participates in group movement without becoming active or editable. |

The important distinction is:

- **Active** owns options and controls.
- **Selected** owns group operations.
- **Editing** owns keyboard input.

Text can remain active without being edited. For code, active currently also means editable.

Shapes follow the same state separation: clicking or creating a shape makes it active without selecting it. Ctrl-click, Cmd-click, or marquee selection can select a shape without making it active. An active shape may also be selected, but changing either state does not change the other.

## Appearance

- New users start in Dark theme and Glass surface style.
- Compile-time flags independently control theme and surface-style selection. With a flag disabled, the app uses Dark or Glass and omits that selector. With both disabled, Settings omits the Appearance section. Enabling a flag restores its selector and normal preference persistence.
- App-wide surface style controls the backgrounds of future text and code blocks. Existing and pasted blocks retain their backgrounds and per-block options.

## Text blocks

- Clicking the preview makes the block active, opens the Markdown source editor, and focuses it.
- Dragging the preview moves the block without activating it.
- Using an option or starting a move or rotation closes the source editor but leaves the block active. Options and transform controls remain available.
- Resizing is available whenever the block is active, including while editing.
- Clicking empty canvas or another block, changing tools, or pressing Escape returns the block to its inactive preview.
- Text options control font, color, and background. New text blocks use the theme's heading and body colors; picking a color applies that fixed color to both. Existing saved custom colors remain fixed when switching themes. The Background dropdown offers Transparent, Card, and Glass; new text blocks use Glass in app-wide Glass mode and Card in Solid mode. Changing the app mode affects only future blocks; existing and pasted blocks retain their backgrounds. Transparent hides the surface, shadow, and preview border while preserving editing borders and selection highlighting. Glass blurs the canvas behind its rounded bounds and retains a translucent surface and fine border without a shadow during preview, activation, and editing. Selected Glass keeps its blur and translucency with an accent tint and outline.

## Code blocks

- Clicking the read-only code surface or title activates the block and makes its source and title editable.
- Dragging the inactive surface or title moves the block without activating it or leaving a code selection behind.
- The active state exposes the editable source and title, language picker, resize handle, and move, rotate, arrange, and delete controls.
- The options panel controls line-number visibility and background. The Background dropdown offers Transparent, Card, and Glass; new code blocks use Glass in app-wide Glass mode and Card in Solid mode. Changing the app mode affects only future blocks; existing and pasted blocks retain their backgrounds. The choice applies to the body, title, and line-number area. Transparent removes fills, shadows, and inactive borders while retaining editing borders and selection highlighting. Glass blurs the canvas behind the rounded body and visible title, with a translucent surface and fine border without a shadow in inactive and active states. Selected Glass retains its blur and translucency with an accent tint and outline. Each background change affects only the active block and is one undoable operation.
- Moving or rotating through the floating controls keeps the block active and editable.
- Clicking away or pressing Escape returns the block to its read-only preview. An empty title is hidden while inactive. The title belongs to the block's layout and stacking layer; its strip remains reserved when hidden without changing the body's position, dimensions, or rotation pivot.

## Media blocks

- Media does not switch between separate preview and editor surfaces: the image remains visible in both inactive and active states.
- Clicking an image activates it and reveals its URL panel, resize handle, and top-left transform controls, including Arrange. Dragging an inactive image moves it without activating it.
- A URL-only media block keeps its URL field visible. While active it exposes move, arrange, and delete controls; rotation becomes available after an image resolves.
- Moving, rotating, or resizing keeps the block active. Resizing preserves the image aspect ratio and follows the element's rotated axes.
- Clicking empty canvas or another block, changing tools, or pressing Escape deactivates the block and hides its active controls.

## Pen strokes

- The pen remains enabled after each stroke until it is toggled off, another tool is chosen, or Escape is pressed.
- Persisted strokes have no active state, options, or transform controls. Pen options apply only to newly drawn strokes.
- Primary-button dragging moves a stroke directly. Modifier-click and marquee selection are the only ways to select strokes.
- Selected strokes participate in group movement and keyboard deletion.

## Undo and redo

- Document undo and redo clear selection, activation, and editing while preserving surviving objects of the same ID and type, their controllers, scroll positions, and loaded images. Changed image sources and restored deleted objects load normally. File switching and imports replace the document completely.

- Document restoration, replacement, removal, and disposal cancel pending editor pastes and image uploads, including work targeting unchanged surviving objects. Canceled uploads attempt to delete their newly written attachment when a pending write finishes. Leaving editing, changing tools, and tool-only undo or redo keep pending edits alive. Ordinary image loads continue when their source is unchanged.

- Explicit tool choices, switching tools, toggling a tool off, and Escape disabling a tool each form one undo step. Touch Select is included; choosing it from another tool is one step.
- Undoing a stroke keeps the pen enabled. Another Undo reverses choosing the pen. Redo restores these actions in order.
- Undoing object placement re-enables its placement tool. Automatically returning to Select belongs to the placement operation and does not add a separate step.
- Tool-only undo and redo preserve canvas contents and object selection without saving the document. Drawing defaults, object selection, and activation are not history operations.
- New tool choices or document edits clear redo. Tool choices share the latest 50 operations with document edits; switching files or replacing a document resets history and tools.

## Arrows

- Drawing an arrow makes it active and returns to the select tool.
- Arrow options set the color, solid or dashed shaft style, and width for newly drawn arrows.
- Activating an existing arrow exposes the same options; edits affect only that arrow and keep its arrowhead solid.
- Hold the primary mouse button and drag to draw an arrow. Each secondary-button press while the primary remains held fixes a Bézier control handle at the cursor; the arrowhead continues following the cursor. Holding the secondary button adds only one handle. Releasing the primary commits the arrow, even if the secondary remains held.
- Drawing without secondary clicks keeps the automatic bend. The first click replaces that bend with a fixed control handle; further clicks add handles in order. Added handles and guides appear during drawing.
- Curves use smooth quadratic Bézier sections joined at midpoints between controls. Handles pull the curve toward them and affect nearby bends; the curve does not have to pass through them.
- Clicking an existing arrow activates it; dragging an inactive arrow moves it without activation. Auto arrangement promotes it on click or drag; an Auto-off active arrow keeps its temporary lift.
- An active arrow shows its start, all control handles, and arrowhead with Bézier guides. Primary-button dragging a point reshapes only that arrow and forms one undoable operation. Secondary dragging by itself still pans the canvas.
- Dashed gaps remain part of the arrow's pointer target.

## Drag and selection rules

- Dragging an inactive, unselected block moves only that block and clears any unrelated selection.
- Dragging any member of a selected group moves the whole group.
- Ctrl-click, or Cmd-click on macOS, toggles selection without activating the block.
- Escape clears canvas selection, including inactive selected objects. While a menu or file picker is open, Escape follows that surface's dismissal rules first.
- Resizing affects one block and clears group selection.
- Movement remains aligned with screen direction under canvas zoom and element rotation. Screen deltas are converted to canvas coordinates before persistence.
- Transform controls rotate with their block and remain anchored to its top-left corner.
- Scrolling inside bounded text or code content does not pan the canvas.
- Dropdowns, context menus, and submenus absorb pointer scrolling over their contents, search fields, and padding, including at either scroll limit or when no scrolling is needed.
- Primary-button gestures perform block activation, editing, and movement. In the Select tool, a secondary click opens the object menu; secondary dragging still pans. Drawing tools retain their secondary-button gestures.

## Stacking order

- Document order runs from back to front. New and pasted objects append at the front; pasted objects preserve their internal order.
- Activation temporarily brings the whole block, including its title, above the stack for painting and pointer targeting. Clicking away, Escape, or changing tools removes this lift. Moving, rotating, or resizing an active block keeps its lift.
- Auto is a saved per-object setting, enabled by default for every element, including elements loaded without an explicit setting. Clicks, taps, modifier-clicks, right-clicks, editing, and transforms bring Auto-on objects permanently to the front. Hover, marquee selection, and canvas navigation do not change layers. Saving and reopening preserve document order.
- Taps inside an active text or code editor and Markdown link clicks also promote the block without restarting editing or changing link behavior. Content edits, including completed pastes, promote the block; restoring saved content and changing only the text selection do not.
- Dragging a selected group promotes only its Auto-on members, retaining their relative order. Auto-off members keep their saved layers. Auto-off objects still receive the temporary foreground lift while active.
- Each automatic promotion is undoable. A drag or transform and its promotion share one undo step; interactions that do not change order add no history entry.
- Entering Arrange ends editing and activation and reveals the saved order before the menu opens or a shortcut changes it. Arrange changes stay visible after dismissal.
- The Layers control between Rotate and Delete opens a titled Arrange popover beside the active block's controls, preferring the left when it fits. It selects that block, ends editing and activation, and hides its controls. The popover stays upright and within the viewport under zoom and rotation and uses the app's Solid or Glass surface. Dismissal leaves the block selected and inactive.
- The new Arrange control currently throws `UnimplementedError` when the active block belongs to a multi-object selection, preserving that selection and activation. Selected groups need their own menu for move, rotate, arrange, and delete; existing context menus and shortcuts still support group arrangement.
- Arrange starts with an Auto switch using the same slider toggle as line numbers. For a group it shows on only when every target has Auto enabled; toggling applies to all captured targets and dismisses the menu. Enabling Auto immediately brings the targets to the front as one undo step; disabling it retains their order.
- Arrange also offers Bring Forward, Send Backward, Bring to Front, and Send to Back. Forward and Backward cross the nearest overlapping object; Front and Back move to the ends of the stack. Groups retain their internal order, and other objects retain theirs. Choosing a manual command or shortcut disables Auto for its targets.
- Each successful Arrange command saves the order and Auto settings together as one undo step. Boundary commands remain enabled while any target has Auto on, even if the order cannot change, so choosing them can disable Auto. With Auto off, commands that cannot change order are disabled and make no history entry. If an object's layout size is not known, overlap commands are disabled; stack-end commands remain available.
- Cmd on macOS, or Ctrl elsewhere, plus `]` brings forward and `[` sends backward. Adding Shift brings to front or sends to back. Shortcuts target the selection, falling back to the active object, and support key repeat. A fallback object becomes selected before deactivation so repeated shortcuts retain their target. Focused editors keep these keys while the menu is closed.

## Object context menu

- In the Select tool, secondary-button release on an object opens a menu containing Cut, Copy, Paste, Arrange, and Delete when movement stays within 4 logical pixels of the press position. The canvas stays still within that distance; crossing it commits to panning, even if the pointer returns to the press position. Right-clicking empty canvas opens a Paste-only menu, preserves selection, and ends editing and activation. Touch long-press has no object menu.
- Right-clicking a selected object targets its selected group. Right-clicking an unselected object makes it the sole selection. Neither activates an object nor enters editing.
- Right-clicking an editor captures its target, preserves content, ends editing and activation, and transfers keyboard focus to the menu. Editor context menus do not compete with the canvas menu. Menu clicks count as object-control interaction, including for active media.
- Menus stay upright and use screen coordinates under zoom and rotation. Hover, click, arrow keys, Enter, and Escape use Flutter's menu navigation. While open, the menu owns keyboard input and Cut, Copy, Delete, and Arrange shortcuts use the targets captured on opening. Paste uses the canvas location captured on opening, including under zoom. The first enabled item receives focus.
- Menu actions close the menu before dispatch. Cut deletes its captured targets only after a successful clipboard write; failed access shows the existing clipboard error. Copy leaves the document unchanged. Cut, Delete, and Paste each save as one undoable operation. Delete is immediate and Undo restores it.
- Paste retains canvas objects, images, and media URL support. Inserted content is centered at the captured location and becomes selected. Pointer movement during a clipboard read does not change the destination; document replacement cancels pending insertion or cutting. Clipboard menu actions are disabled when direct clipboard access is unavailable, while browser clipboard events retain native shortcut access.
- Dismissing the menu preserves selection and leaves blocks inactive. Navigation, tool changes, file-picker opening, target deletion, document replacement, and leaving the page close it.

## Touch navigation

| Action | Select off | Select on |
| --- | --- | --- |
| Drag empty canvas | Pan | Draw a selection box |
| Drag an unselected object | Move that object | Move that object |
| Drag a selected object | Move the selected group | Move the selected group |
| Tap an object | Existing activation or editing behavior | Same behavior |
| Tap empty canvas | Clear activation and selection | Same behavior |
| Two fingers | Pan and pinch zoom | Pan and pinch zoom |

- Select changes only empty-canvas touch dragging. It stays enabled after box selection until tapped again, another tool is chosen, or the document is replaced. Turning Select off preserves selected objects and their direct group movement.
- The Select button appears initially on Android/iOS platform classification. Elsewhere, the first actual touch anywhere on the page or its controls reveals it after all touches and release callbacks finish. It remains visible until reload; mouse, stylus, keyboard, hover, and screen width do not hide or reveal it. Visibility and Select mode are not persisted.
- Movement below Flutter's touch threshold remains a tap. With Select off, crossing the threshold pans with the full drag displacement without changing selection. Normal release can continue panning with inertia; cancellation does not.
- With Select on, crossing the threshold draws the selection box using the existing overlap rules, including zoom and rotated bounds. Cancellation, two-finger takeover, or a tool change restores the prior selection and removes the unfinished box.
- Tapping empty canvas clears activation and selection on release. Dragging an object moves it directly; dragging a selected member moves the selected group.
- Escape first dismisses active editing or object controls as before, then disables Select on the next press. Mouse marquee and modifier selection keep their existing behavior in either mode.
- One finger also draws, erases, places objects, or interacts with object controls when those tools are enabled. Two fingers pan and pinch to zoom, including when a finger starts on an object control or code title.
- Adding a second finger cancels a pending or active single-finger pan without a jump or fling. Changing tools or replacing the document also cancels the pan; held pointers cannot restart it.
- Adding a second finger discards unfinished pen, arrow, and shape drawings and pending placement. Erasures and object moves, resizes, rotations, and arrow-point edits already made are kept as one undoable operation.
- After navigation drops to one finger, the remaining finger does nothing until all touches lift. Interrupted pointers cannot resume editing; an interrupted stylus must also lift before tools resume.
- Text, code, and media are placed on single-finger touch tap release. Dragging, cancellation, or adding a second finger cancels placement. Mouse and stylus placement happen on press.
- A stylus and one finger do not start navigation. Two actual fingers can take over and discard an unfinished stylus drawing.

## Canvas files

- Clicking the canvas title opens the file picker; hovering the title reveals its folder path.
- Clicking a canvas saves the current file and opens the chosen one. Each file has separate contents; switching clears undo and selection state.
- Clicking a folder expands or collapses it. Header actions create root-level canvases and folders; right-click a folder to create items inside it.
- Debug builds also show a Demo header button beside New folder and Close. It imports the bundled sample, including its image, into a new root-level canvas and opens it. Names use Demo, Demo 2, and the first available numbered suffix; existing canvases are preserved. The button and bundled sample are excluded from release and profile builds.
- Names are edited inline. Enter or clicking away saves; Escape or an empty name cancels, and duplicate sibling names are rejected. Clicking another canvas saves the edit and opens that canvas. Right-click an item to rename or delete it; deletion requires confirmation.
- Drag a file or folder above or below a row to place it beside that item. Drop on the center of a folder row to move inside it. A folder moves with its contents; moves that create a folder cycle or duplicate sibling name are rejected.
- While the picker is open, keyboard input belongs to the picker. Escape, the close button, or clicking outside dismisses it; a pending nonempty name is saved before click-away dismissal, while Escape in a name field cancels only that edit.
- Files, folders, and the last-opened canvas persist in this browser. Failed saves keep the current canvas open and preserve entered names for retry.
- Settings > Data can export or import one canvas, or back up and restore the library as a ZIP containing the folder tree, canvas JSON files, and images. Import confirms replacement of the active canvas; restore validates the ZIP and confirms replacement of the whole library. Canceling either leaves the library unchanged. Restore opens the first canvas by ZIP path; file order is not preserved.
