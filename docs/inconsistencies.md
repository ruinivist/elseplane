# UI inconsistencies

What this repo does: Elseplane is a Flutter infinite canvas for Markdown, code, shapes, and media. This audit assumes one person using the web app with a pointer and keyboard.

Reviewed revision: `c3476a8`. Three subagents reviewed shared UI and theme, canvas presentation, and settings/library presentation. The scan focused on local styles or custom controls that bypass shared interaction states. It found **seven categories**, grouped by cause rather than counting every affected widget.

The baseline is [the shared action style](../lib/theme/starless.dart), lines 273–292: ordinary buttons use `surfaceHover` for hover and focus, `surfacePressed` for press, a `focusRing` outline for keyboard focus, and `textMuted` when disabled. Their overlay is transparent, so feedback is painted once. [UI guidance](../lib/ui/AGENTS.md) says ordinary actions inherit these states. Component layout and selection markers can remain local.

## Must fix

### 1. Dropdown triggers lose keyboard focus styling

Locations: [select.dart](../lib/ui/common/select.dart), lines 66–96 and 192–196. Affected controls include Canvas Background, appearance selectors, font, and language.

- **What this is:** `Select` and `SearchableSelect` replace the button background, border, and foreground rules.
- **Problem:** Tab to a closed dropdown: its style has no focused background or border branch, so it looks idle. Disabled labels also use a separate opacity rule while the explicitly colored chevron stays at full strength. The font selector has a real disabled state while loading a font.
- **Fix:** Keep the dropdown's idle surface and layout, but preserve the shared focus states and disabled foreground role. Let the chevron inherit the button foreground.
- **If we skip it:** Keyboard users cannot see which closed dropdown has focus, and a disabled selector's label and arrow disagree about its state.

### 2. Arrange and Delete bypass themed buttons entirely

Locations: [element_transform_controls.dart](../lib/canvas/editor/widgets/element_transform_controls.dart), lines 79–124; [canvas_view.dart](../lib/canvas/editor/canvas_view.dart), lines 445–448 and 1114–1123.

- **What this is:** These two click actions use `MouseRegion`, `GestureDetector`, and manually colored icons instead of buttons.
- **Problem:** Hover and press produce no shared button feedback. Tab cannot reach either action, so Enter and Space cannot activate them, unlike toolbar and settings actions.
- **Fix:** Use themed `IconButton` controls. Preserve labels, transformed menu bounds, tap regions, and the outer pointer listener. For keyboard Arrange, use current selection when no pointer capture exists: the current callback reads `selectionBeforePointer`, which could otherwise be stale.
- **If we skip it:** The same kind of click action has different feedback and keyboard access depending on where it appears. Move and Rotate should remain drag controls.

## Should fix

### 3. The current file row covers its own interaction feedback

Location: [file_tree_popup.dart](../lib/library/widgets/file_tree_popup.dart), lines 327–364.

- **What this is:** File rows use `InkWell` feedback and a child `Container` for the current-file or editing background.
- **Problem:** The opaque child background paints above the ancestor Material's ink. It hides hover, focus, and pressed feedback on those rows, while transparent rows show it. The current-file marker and keyboard focus are supposed to be independent.
- **Fix:** Paint the row background with `Ink`, retaining its size, padding, and current-file marker, so the decoration and feedback share the Material ink layer.
- **If we skip it:** Moving keyboard focus onto or off the current file can have no visible effect on that row.

### 4. Dropdown options receive an extra Flutter overlay

Locations: [select.dart](../lib/ui/common/select.dart), lines 121–141; comparison: [menu_surface.dart](../lib/ui/common/menu_surface.dart), lines 31–54.

- **What this is:** Dropdown options set their own hover, pressed, selected, and search-highlight backgrounds.
- **Problem:** Their style leaves `overlayColor` unset. `MenuItemButton` does not inherit `TextButtonTheme`; Flutter adds its default foreground tint over the background. Context-menu rows explicitly control their overlay. Searchable dropdown keyboard highlighting can also differ from mouse hover because only the latter adds the native hover tint.
- **Fix:** Make option overlays transparent and let the existing background resolver own feedback once. Retain selected and search-highlight states.
- **If we skip it:** Dropdown rows and context-menu rows keep different hover colors despite using the same semantic hover value. This is the closest remaining match to the About bug.

### 5. Selection borders override keyboard focus borders

Locations: [color_picker.dart](../lib/ui/common/color_picker.dart), lines 57–65; [shape_tool_settings.dart](../lib/canvas/editor/elements/shape/shape_tool_settings.dart), lines 89–97.

- **What this is:** Color swatches and No fill assign a fixed `side` based only on selection.
- **Problem:** That border replaces the theme's state-aware focus border. An unselected focused control keeps a transparent border, while a selected unfocused control displays the same ring color used for focus. The inherited focus background still works; focus feedback is reduced, not completely absent.
- **Fix:** Keep a distinct selection marker while preserving the theme's focused border, for example by putting the selected marker inside the icon content.
- **If we skip it:** Keyboard focus outlines differ between these controls and the adjacent custom-color toggle or ordinary buttons.

### 6. Canvas title and Settings navigation recreate partial button states

Locations: [canvas_title.dart](../lib/library/widgets/canvas_title.dart), lines 69–78; [settings_dialog.dart](../lib/settings/settings_dialog.dart), lines 267–275.

- **What this is:** Both click actions use `InkWell` directly and bypass the theme's button styles.
- **Problem:** Canvas title uses the global focus color as a filled highlight instead of the shared focus outline. Settings navigation locally specifies a focus fill without that outline. Both leave the pressed highlight to Flutter's default `highlightColor`; setting `splashColor` does not set the pressed highlight, and the app disables splashes with `NoSplash`.
- **Fix:** Use themed `TextButton` controls, keeping breadcrumb expansion, navigation selection, and layout local.
- **If we skip it:** Focus and press feedback varies between these actions and the close, data-transfer, and About buttons beside them.

## Nice to have

### 7. Some panels omit the shared smooth pointer scrolling

Locations: [settings_dialog.dart](../lib/settings/settings_dialog.dart), lines 166–169 and 185–202; [surface_dialog.dart](../lib/ui/common/surface_dialog.dart), line 51; [canvas_chrome.dart](../lib/canvas/editor/widgets/canvas_chrome.dart), lines 45–49.

- **What this is:** Settings, confirmation content, and the title's horizontal overflow use bare `SingleChildScrollView` widgets.
- **Problem:** When dialog content overflows a short viewport, wheel scrolling uses Flutter's default behavior. An overflowing canvas title has the same difference with Shift + mouse wheel or horizontal wheel input. File-picker rows, menu content, and tool options use the installed `scroll_animator` pattern. Project guidance requires `scroll_animator` 0.3.0 with `ChromiumEaseInOut`.
- **Fix:** Use the existing `AnimatedPrimaryScrollController` pattern for these scroll areas, as the file picker and menu surface already do.
- **If we skip it:** Pointer scrolling feels different between dialogs and other app panels.

## Differences that are justified

- `ToolbarButton` adds selected-state styling while deferring other button backgrounds to the theme. Zoom reveal and muted readout styling also preserve shared button states.
- Circular swatches, compact file-tree controls, breadcrumb expansion, and component padding have specific roles. Equal numeric sizes alone do not establish an inconsistency.
- Move, Rotate, Resize, and arrow handles need drag gestures. They are not ordinary click buttons.
- Saved element colors, backgrounds, and Markdown typography describe document content, not app controls.
- Glass surfaces, native menu-shell transparency, color gradients, and checkerboards implement their component roles.
- The About fix is present: both links inherit shared background states. Its explicit transparent overlay prevents `styleFrom(foregroundColor: ...)` from generating another tint for the muted Build link.

## Coverage and limits

Read production presentation in `lib/ui/common`, `lib/theme`, `lib/settings`, `lib/library/widgets`, `lib/app`, canvas widgets and element views, plus relevant callers and existing tests. Reviewed preview themes and scanned platform entry points and web startup styling. Flutter's installed source confirms the menu overlay and Material ink behavior described above.

**Verdict:** Fix dropdown focus and the custom Arrange/Delete actions first. The seven categories are concentrated in shared controls and a few custom click actions.

**Lean:** No new dependencies are needed. Line savings were not estimated; this report changes no implementation.

**Not checked:** Browser rendering, runtime interaction, or tests. This is a source audit of UI consistency, not a general correctness, security, or performance audit. Findings need a focused browser check when fixed; no automated behavior checks were added.
