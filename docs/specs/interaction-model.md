# Interaction model

Status: accepted.

## Scope

This specification governs supported canvas editing, controls, history,
stacking, and file workflows. Ordinary touch navigation and native control or
editor interactions are best effort; full touchscreen canvas editing is not a
supported workflow.

## Acceptance criteria

- Keep activation, selection, and editing independent, with the per-object and
  group operations described below.
- Keep supported mouse, keyboard, touchpad, and stylus workflows consistent
  across creation, editing, history, menus, and arrangement.
- Cancel asynchronous edits at the documented logical-context boundaries,
  preserve completed edits, and follow the accepted paste-cancellation ADR.
- Keep file switching and import/restore behavior consistent with the
  persistence and failure rules below.

## Behavior

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

### Appearance

- New users start in Dark theme and Glass surface style.
- Compile-time flags independently control theme and surface-style selection. With a flag disabled, the app uses Dark or Glass and omits that selector. With both disabled, Settings omits the Appearance section. Enabling a flag restores its selector and normal preference persistence.
- All glass surfaces, including toolbars, menus, and dialogs, use a faint, centered halo outside their rounded bounds; the shadow does not darken the translucent interior.
- The first color preset is White, matching the Dark theme’s body-text shade. New text, pen strokes, shape outlines, and arrows default to this fixed color; shapes start without a fill. Existing objects retain their saved colors.
- App-wide surface style controls the backgrounds of future text and code blocks. Existing and pasted blocks retain their backgrounds and per-block options.

### Text blocks

- In Select, primary mouse double-click on empty canvas creates a transparent text block at the second press position, above existing objects, and immediately focuses its Markdown editor. Both clicks must land on empty canvas; clicking an object or its controls cancels insertion. Normal Text-tool placement keeps its app-wide background default.
- Single clicks retain their normal target routing and timing, including object activation. Any attached element-target pointer press cancels quick-text recognition, so object-to-empty and empty-to-object click pairs do not insert text. Gestures starting inside an already focused text, code, title, or media field retain native editing behavior. Menus, toolbars, option panels, transform controls, modifier selection, Space panning, and stylus input do not trigger insertion. Dragging, navigation, interruption, and tool or document changes cancel pending recognition.

- Clicking the preview makes the block active, opens the Markdown source editor, and focuses it.
- Dragging the preview moves the block without activating it.
- Using an option or starting a move or rotation closes the source editor but leaves the block active. Options and transform controls remain available.
- Resizing is available whenever the block is active, including while editing.
- Clicking empty canvas or another block, changing tools, or pressing Escape returns the block to its inactive preview.
- Text options control font, color, and background. New text blocks use the first color preset for both headings and body text; picking a color applies that fixed color to both. Saved blocks without an explicit color continue to use the theme’s heading and body colors. Existing saved custom colors remain fixed when switching themes. The Background dropdown offers Transparent, Card, and Glass; new text blocks use Glass in app-wide Glass mode and Card in Solid mode. Changing the app mode affects only future blocks; existing and pasted blocks retain their backgrounds. Transparent hides the surface, shadow, and preview border while preserving editing borders and selection highlighting. Glass blurs the canvas behind its rounded bounds and retains a translucent surface, fine border, and faint exterior shadow during preview, activation, and editing. Selected Glass keeps its blur and translucency with an accent tint and outline.
- Saved font names remain valid when a font is unavailable or absent from the current catalog. The picker preserves the saved name, and previews render the bundled font until the requested font can load.

### Code blocks

- Code lines never wrap; long lines scroll horizontally. Wrapping is fixed off and has no user option.
- Clicking the read-only code surface or title activates the block and makes its source and title editable.
- Dragging the inactive surface or title moves the block without activating it or leaving a code selection behind.
- The active state exposes the editable source and title, language picker, resize handle, and move, rotate, arrange, and delete controls.
- The options panel controls line-number visibility and background. The Background dropdown offers Transparent, Card, and Glass; new code blocks use Glass in app-wide Glass mode and Card in Solid mode. Changing the app mode affects only future blocks; existing and pasted blocks retain their backgrounds. The choice applies to the body, title, and line-number area. Transparent removes fills, shadows, and inactive borders while retaining editing borders and selection highlighting. Glass blurs the canvas behind the rounded body and visible title, with a translucent surface, fine border, and faint exterior shadow in inactive and active states. Selected Glass retains its blur and translucency with an accent tint and outline. Each background change affects only the active block and is one undoable operation.
- Moving or rotating through the floating controls keeps the block active and editable.
- Clicking away or pressing Escape returns the block to its read-only preview. An empty title is hidden while inactive. The title belongs to the block's layout and stacking layer; its strip remains reserved when hidden without changing the body's position, dimensions, or rotation pivot.

### Media blocks

- Media does not switch between separate preview and editor surfaces: its content remains visible in both inactive and active states.
- Media elements save their source URL and geometry only; there is no saved display kind, automatic mode, or manual Image/Link selector. Local attachments continue to use the existing attachment-path checks. For an external URL, show an image only when `URI.path` ends in `.png`, `.jpg`, `.jpeg`, `.gif`, or `.webp`, ignoring case. Query and fragment text do not affect the path suffix. Every other valid HTTPS URL is a link. Do not probe remote content to infer image type; extensionless remote images deliberately become generic link cards. Uploading or pasting image bytes creates a local image attachment.
- Accept new or edited external sources only when they are valid HTTPS URLs no longer than 2048 characters. The same pure URL rule applies to the URL field, plain-link paste, serialized clipboard media, project import, and library restore. Empty sources and invalid legacy sources show the unresolved URL panel. Existing browser data with arbitrary source strings remains readable and is not rewritten, but invalid sources are never loaded or opened. Do not tighten the global document decoder to enforce this rule on already stored data.
- The URL field retains the existing commit rule: Enter or leaving the field applies the value, including Escape; typing or pasting text alone does not change the saved URL or current content. Invalid drafts are not saved, requested, or opened. Device selection and image paste apply immediately. Reject unsafe or invalid imported sources before attachment staging or publication; failure leaves the current document, history, and attachments unchanged.
- Clicking an image activates it and reveals its URL panel, resize handle, and top-left transform controls, including Arrange. Clicking an unresolved block activates it and focuses the URL field. The device image button opens the picker with one click, including while inactive. While active, the URL field supports normal caret movement and text selection, and the block exposes move, arrange, and delete controls. An inactive media block moves on drag without activation; body clicks do not open links. The active link card exposes an accessible Open link action for the original URL in a new tab; launch failure remains visible. Rotation is available for resolved images and links.
- Generic links display host and path without query or fragment, but retain the full original URL for saving and opening. Only YouTube, Vimeo, Spotify, and SoundCloud links receive best-effort metadata from public CORS-enabled oEmbed endpoints. Use exact allowlisted hosts and one shared loader/parser and normalized metadata model. Build canonical provider requests without unrelated query parameters or fragments. Enforce finite URL and metadata size limits, accept only bounded plain-text metadata and validated HTTPS thumbnails from allowlisted hosts, and ignore returned HTML. Other links receive no metadata, network, or image-type probe.
- Provider metadata requests start only when a card is visible. Apply a five-second timeout with no retries; on failure, show generic host/path content in the unchanged provider footprint. Retain source-keyed runtime metadata and thumbnail resources across culling, and ignore completions for changed sources, removed cards, or replaced documents. Metadata and thumbnail results never change geometry or add history entries.
- Enriched provider cards default to 480 by 360; generic links default to 480 by 112. Each footprint stays fixed while loading and after failure. Images and links share their movement, rotation, and resize behavior. Moving, rotating, or resizing keeps the block active; resize preserves content proportions and follows the element's rotated axes.
- Link cards do not play media or embed iframe players. Provider metadata and thumbnails are runtime-only, are not stored in canvas documents or ZIP exports, and may be unavailable offline. Requests to a supported provider disclose the canonical media URL to that provider.
- Clicking empty canvas or another block, changing tools, or pressing Escape deactivates the block and hides its active controls.

### Pen strokes

- The pen remains enabled after each stroke until it is toggled off, another tool is chosen, or Escape is pressed.
- Persisted strokes have no active state, options, or transform controls. Pen options apply only to newly drawn strokes.
- Primary-button dragging moves a stroke directly. Modifier-click and marquee selection are the only ways to select strokes.
- Selected strokes participate in group movement and keyboard deletion.

### Undo and redo

- Document undo and redo clear selection, activation, and editing while preserving surviving objects of the same ID and type, their controllers, scroll positions, and loaded images. Changed image sources and restored deleted objects load normally. File switching and imports replace the document completely.

- [Unfinished pastes belong to their original input context](../adr/0001-cancel-unfinished-pastes.md). Selecting another field or object, explicitly ending editing, changing tools (including tool-only undo or redo), opening an app dialog or file picker, document restoration, replacement, removal, and disposal cancel affected pending pastes and image uploads. Code source and title are separate contexts; returning to a field does not revive canceled work. Temporary browser focus loss, clipboard permission prompts, and the device image picker do not cancel work. Ordinary typing, caret movement, and transforms that keep the same editor open preserve the context and use its live selection. Canceled writes attempt cleanup of their new unpublished attachment paths. Cancellation is silent; current-context failures remain visible. Ordinary image loads continue when their source is unchanged.

- Canvas history groups text and code changes by logical field. Moving between code source and title, ending editing, or starting another document operation closes the group. Temporary browser focus loss does not split it. A placement is separate from subsequent typing; its automatic return to Select remains part of placement.

- Explicit tool choices, switching tools, toggling a tool off, and Escape disabling a tool each form one undo step.
- Undoing a stroke keeps the pen enabled. Another Undo reverses choosing the pen. Redo restores these actions in order.
- Undoing object placement re-enables its placement tool. Automatically returning to Select belongs to the placement operation and does not add a separate step.
- Tool-only undo and redo preserve canvas contents and object selection without saving the document. Drawing defaults, object selection, and activation are not history operations.
- New tool choices or document edits clear redo. Tool choices share the latest 50 operations with document edits; switching files or replacing a document resets history and tools.

### Arrows

- Drawing an arrow makes it active and returns to the select tool.
- Arrow options set the color, solid or dashed shaft style, and width for newly drawn arrows.
- Activating an existing arrow exposes the same options; edits affect only that arrow and keep its arrowhead solid.
- Hold the primary mouse button and drag to draw an arrow. Each secondary-button press while the primary remains held fixes a Bézier control handle at the cursor; the arrowhead continues following the cursor. Holding the secondary button adds only one handle. Releasing the primary commits the arrow, even if the secondary remains held.
- Drawing without secondary clicks keeps the automatic bend. The first click replaces that bend with a fixed control handle; further clicks add handles in order. Added handles and guides appear during drawing.
- Curves use smooth quadratic Bézier sections joined at midpoints between controls. Handles pull the curve toward them and affect nearby bends; the curve does not have to pass through them.
- Clicking an existing arrow activates it and clears canvas selection. Dragging an inactive, unselected arrow moves it without activation or selection; dragging a selected arrow preserves its selected group. Auto arrangement promotes it on click or drag; an Auto-off active arrow keeps its temporary lift.
- An active arrow shows its start, all control handles, and arrowhead with Bézier guides. Primary-button dragging a point reshapes only that arrow and forms one undoable operation. Secondary dragging by itself still pans the canvas.
- Dashed gaps remain part of the arrow's pointer target.

### Drag and selection rules

- Dragging an inactive, unselected block moves only that block and clears any unrelated selection.
- Dragging any member of a selected group moves the whole group.
- Ctrl-click, or Cmd-click on macOS, toggles selection without activating the block.
- Escape clears canvas selection, including inactive selected objects. While a menu or file picker is open, Escape follows that surface's dismissal rules first.
- Resizing affects one block and clears group selection.
- Movement remains aligned with screen direction under canvas zoom and element rotation. Screen deltas are converted to canvas coordinates before persistence.
- Transform controls rotate with their block and remain anchored to its top-left corner.
- Scrolling inside bounded text, code, or tool-option panels does not pan the canvas, including at their scroll limits or when no scrolling is needed.
- Focused dropdown triggers open with Up, Down, Enter, or Space. Plain dropdowns focus the selected option and use Flutter's menu navigation. Searchable dropdowns keep typing focus in the search field: Down initially highlights the first result and Up the last; subsequent arrows move one result and stop at the ends, scrolling it into view. Enter chooses the highlighted result, or the first match before navigation. Hovering results keeps search focused without moving the keyboard highlight. The search field stays visible while the results list shrinks to fit short windows. Typing resets navigation; no results makes arrows and Enter do nothing. Escape dismisses without changing the value and restores trigger focus. Open dropdowns own keyboard input before canvas commands.
- Dropdowns, context menus, and submenus absorb pointer scrolling over their contents, search fields, and padding, including at either scroll limit or when no scrolling is needed.
- Primary-button gestures perform block activation, editing, and movement. In the Select tool, a secondary click opens the object menu; secondary dragging still pans. Drawing tools retain their secondary-button gestures.

### Stacking order

- Document order runs from back to front. New and pasted objects append at the front; pasted objects preserve their internal order.
- Activation temporarily brings the whole block, including its title, above the stack for painting and pointer targeting. Clicking away, Escape, or changing tools removes this lift. Moving, rotating, or resizing an active block keeps its lift.
- Auto is a saved per-object setting, enabled by default for every element, including elements loaded without an explicit setting. Clicks, modifier-clicks, right-clicks, editing, and transforms bring Auto-on objects permanently to the front. Hover, marquee selection, and canvas navigation do not change layers. Saving and reopening preserve document order.
- Interaction inside an active text or code editor and Markdown link clicks also promote the block without restarting editing or changing link behavior. Content edits, including completed pastes, promote the block; restoring saved content and changing only the text selection do not.
- Dragging a selected group promotes only its Auto-on members, retaining their relative order. Auto-off members keep their saved layers. Auto-off objects still receive the temporary foreground lift while active.
- Each automatic promotion is undoable. A drag or transform and its promotion share one undo step; interactions that do not change order add no history entry.
- Entering Arrange ends editing and activation and reveals the saved order before the menu opens or a shortcut changes it. Arrange changes stay visible after dismissal.
- The Layers control between Rotate and Delete opens a titled Arrange popover beside the active block's controls, preferring the left when it fits. It selects the target block or preserves its selected group, ends editing and activation, and hides its controls. The popover stays upright and within the viewport under zoom and rotation and uses the app's Solid or Glass surface. Escape dismissal leaves the block selected and inactive; outside clicks follow the normal click and drag rules.
- When the active block belongs to a multi-object selection, its Layers control opens Arrange for that whole group. The selection captured before the control press is retained, editing and activation end, and commands use the captured targets until dismissal. If the active block is outside the selection, Arrange targets only that block. Escape preserves the captured group selection; outside clicks follow the normal click and drag rules. Additional group transform controls require separate product design.
- Arrange starts with an Auto switch using the same slider toggle as line numbers. For a group it shows on only when every target has Auto enabled; toggling applies to all captured targets and keeps the menu open. Enabling Auto immediately brings the targets to the front as one undo step; disabling it retains their order.
- Arrange also offers Bring Forward, Send Backward, Bring to Front, and Send to Back. Forward and Backward cross the nearest overlapping object; Front and Back move to the ends of the stack. Groups retain their internal order, and other objects retain theirs. A manual command or shortcut that changes order disables Auto for its targets.
- Both the right-click Arrange submenu and the Layers-control Arrange popover stay open after manual commands, Auto toggles, and keyboard activation, including arrangement shortcuts. Each action updates the visible saved order, Auto switch, and command availability immediately, retaining the captured targets until dismissal.
- Each successful Arrange command saves the order and Auto settings together as one undo step. Commands that cannot change order are disabled regardless of Auto; their shortcuts leave order and Auto unchanged and make no history entry. Use the Auto switch to disable Auto without changing order. If an object's layout size is not known, overlap commands are disabled; stack-end commands remain available when they can change order.
- Cmd on macOS, or Ctrl elsewhere, plus `]` brings forward and `[` sends backward. Adding Shift brings to front or sends to back. Shortcuts target the selection, falling back to the active object, and support key repeat. A fallback object becomes selected before deactivation so repeated shortcuts retain their target. Focused editors keep these keys while the menu is closed.

### Object context menu

- In the Select tool, secondary-button release on an object opens a menu containing Cut, Copy, Paste, Arrange, and Delete when movement stays within 4 logical pixels of the press position. The canvas stays still within that distance; crossing it commits to panning, even if the pointer returns to the press position. Right-clicking empty canvas opens a Paste-only menu, preserves selection, and ends editing and activation.
- Right-clicking a selected object targets its selected group. Right-clicking an unselected object makes it the sole selection. Neither activates an object nor enters editing.
- Right-clicking an editor captures its target, preserves content, ends editing and activation, and transfers keyboard focus to the menu. Editor context menus do not compete with the canvas menu. Menu clicks count as object-control interaction, including for active media.
- Menus stay upright and use screen coordinates under zoom and rotation. Hover, click, arrow keys, Enter, and Escape use Flutter's menu navigation. While open, the menu owns keyboard input and Cut, Copy, Delete, and Arrange shortcuts use the targets captured on opening. Paste uses the canvas location captured on opening, including under zoom. The first enabled item receives focus.
- Menu actions close the menu before dispatch, except Arrange commands, Auto toggles, and arrangement shortcuts, which keep it open for repeated use. Cut deletes its captured targets only after a successful clipboard write in the same live context. Canceled Cut leaves the originals untouched even if its system clipboard write finishes. Failed access shows the existing clipboard error. Copy leaves the document unchanged. Cut, Delete, and Paste each save as one undoable operation. Delete is immediate and Undo restores it.
- Paste retains canvas objects, images, and media URL support. Inserted content is centered at the captured location and becomes selected. Pointer movement during a clipboard read does not change the destination; leaving the logical canvas context cancels pending insertion or cutting. Clipboard menu actions are disabled when direct clipboard access is unavailable, while browser clipboard events retain native shortcut access.
- Outside clicks dismiss object menus and the standalone Arrange popover and continue through normal interactions. Ordinary clicks clear all canvas selection and activate or edit the clicked block; empty-canvas clicks clear activation too. Ctrl-click and Cmd-click retain selection toggling, and dragging a selected object still moves its group without activating it. Outside clicks on page controls clear selection and perform the control action. Escape dismisses the current menu level while preserving selection. Navigation, tool changes, file-picker opening, target deletion, document replacement, and leaving the page close menus.

### Touch and supported input

- Canvas editing is supported with mouse, keyboard, touchpad, and stylus.
- Ordinary Flutter touch navigation and native control/editor interactions are best effort, not a supported canvas-editing workflow. Do not globally block touch on buttons, menus, text fields, scrolling, or accessibility surfaces.
- Finger input must not independently start Plane's custom canvas edits while Grid handles touch navigation. There is no touch-only Select mode or discovery, custom touch pan or marquee, finger drawing or erasing, object/control manipulation, touch-release placement, finger double-tap text insertion, or guaranteed two-finger takeover, anchoring, or frame behavior. Mouse double-click text insertion remains supported.

### Canvas files

- Clicking the canvas title or pressing Cmd+P on macOS, Ctrl+P elsewhere, opens the file picker, including while editing. Opening blocks new canvas input, cancels unfinished clipboard and image edits, and saves completed edits before showing the picker. It does not wait for canceled work. Failed saves leave the current canvas open for retry; dismissing the picker or retrying a save does not revive canceled work. Hovering the title reveals its folder path. The shortcut saves and ends editing just like clicking the title; open dropdowns and modal dialogs retain keyboard priority.
- The picker initially focuses the current canvas and scrolls it into view. Up and Down move through visible rows without wrapping or switching files. Right expands a folder or enters its first child; Left collapses a folder or moves to its parent. Enter opens the focused canvas or toggles the focused folder. Keyboard focus is separate from the current-file marker; focused rows stay visible. Name fields retain normal editing keys, and menus and confirmation dialogs own keyboard navigation. Tree navigation is disabled while saving.
- Clicking a canvas saves the current file and opens the chosen one. Each file has separate contents; switching clears undo and selection state.
- Clicking a folder expands or collapses it. Header actions create root-level canvases and folders; right-click a folder to create items inside it.
- Debug builds also show a Demo header button beside New folder and Close. Activating it loads the bundled sample on demand (not at startup), including its image, into a new root-level canvas and opens it. Names use Demo, Demo 2, and the first available numbered suffix; existing canvases are preserved. The button and sample-loading action are debug-only; the ZIP asset is included in all build modes and is not loaded in release or profile builds.
- Names are edited inline. Enter or clicking away saves; Escape or an empty name cancels, and duplicate sibling names are rejected. Clicking another canvas saves the edit and opens that canvas. Right-click an item to rename or delete it; deletion requires confirmation.
- Drag a file or folder above or below a row to place it beside that item. Drop on the center of a folder row to move inside it. A folder moves with its contents; moves that create a folder cycle or duplicate sibling name are rejected.
- While the picker is open, keyboard input belongs to the picker. Escape, the close button, or clicking outside dismisses it; a pending nonempty name is saved before click-away dismissal, while Escape in a name field cancels only that edit.
- Files, folders, and the last-opened canvas persist in this browser. Failed saves keep the current canvas open and preserve entered names for retry.
- Settings > Data exports or imports one canvas as `canvas.elseplane.zip` with the `application/zip` media type. Its `document.json` is the pretty-printed existing versioned `CanvasDocument` JSON. The archive includes each referenced local image once as byte-identical data under `attachments/<uuid>.png`, `.jpg`, `.gif`, or `.webp`; external image URLs remain external. ZIP is a download container, not a canvas document format. Base64 JSON canvas import and export are not supported. The accepted [canvas document and media decision](../adr/0002-separate-documents-and-media.md) records the format and rationale.
- Before expanding entries, canvas archive validation allows only the document and attachment entries, rejects duplicate or unsafe paths and symlinks, and checks declared sizes. After expansion, it verifies actual sizes and checksums and validates document values, image bytes, and attachment references. The compressed archive and total uncompressed content are each limited to 140 MiB; each image is limited to 10 MiB. Import confirms replacement of the active canvas, stages images at fresh unused paths, and remaps their references. Canceling or failing import leaves the current canvas and existing attachments unchanged.
- Library backup and restore keep the existing ZIP layout of the folder tree, canvas JSON files, and images. Restore validates the ZIP and confirms replacement of the whole library; canceling leaves the library unchanged. Restore opens the first canvas by ZIP path; file order is not preserved.
