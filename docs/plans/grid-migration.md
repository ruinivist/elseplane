# Grid migration checklist

Status: active. Implementation and automated verification are complete; physical touchpad/stylus checks remain open. The [interaction model](../specs/interaction-model.md) and [architecture](../arch/README.md) define the updated behavior.

## Baseline

Inspected on 2026-11-05:

- Plane locks `infinite_lazy_grid` to `70e0d7c`; its dependency follows Grid's `main` branch.
- Grid main is `82c3b07`. The intervening changes remove dedicated two-finger navigation and add bounds-aware culling.
- Grid removes `TouchNavigationMode`, `touchNavigationMode`, and `onTouchNavigationChanged`.
- Ordinary finger pan/pinch remains through Flutter's scale recognizer. Mouse, touchpad, wheel, Ctrl-wheel zoom, and exclusion of stylus input from the canvas scale recognizer remain.

Sources in the Grid repository: `README.md`, `CHANGELOG.md`, `TASK.md`, and all five files under `docs/adrs/` and `docs/plans/`. The touch removal is documented in the root files; the ADRs cover culling.

## 1. Review the product direction

Suggested route: support mouse, keyboard, touchpad, and stylus editing. Leave ordinary Flutter touch interaction available where it works, without maintaining a full touchscreen canvas workflow or replacing Grid's removed touch engine.

- [x] Adopt desktop-first editing with best-effort ordinary touch navigation and native control/editor interaction.
- [x] Drop the touch-only Select mode, its toolbar button, and automatic discovery on mobile platforms or first touch.
- [x] Drop guaranteed one-finger drawing, erasing, object movement, touch marquee selection, and control manipulation as supported touchscreen workflows.
- [x] Drop finger double-tap text insertion; keep primary mouse double-click insertion.
- [x] Drop touch-specific release-to-place behavior for text, code, and media; preserve mouse and stylus placement.
- [x] Drop guaranteed two-finger takeover from drawing, editing, placement, titles, and transform controls.
- [x] Drop custom touch-motion guarantees: stationary-finger anchoring, coordinated intermediate frames, coincident-contact handling, original-pair ownership, and draining all fingers before restart.

Dropping a support guarantee does not require disabling every native touch event. It also does not make competing raw tool edits and viewport navigation acceptable. Remove the custom touch editing paths rather than leaving them to run alongside Grid's recognizer. Keep native buttons, menus, text fields, scrolling, and accessibility behavior.

## 2. Update the behavior documents

Do this before implementing the changed interaction policy.

- [x] Replace the detailed touch-navigation section in the interaction specification with the supported-input policy. Remove touch Select history, finger double-tap insertion, release-to-place, and takeover promises elsewhere in the document.
- [x] Update architecture guidance: remove touch-selection mode from history snapshots and mandatory two-finger takeover from input ownership. Keep shared cancellation and lifetime rules.
- [x] Mark the former touch-preservation requirements in the archived refactor record as superseded. Keep historical verification results identified as historical.
- [x] Remove the superseded touch requirements and their links; the custom frame-by-frame acceptance contract no longer applies.
- [x] Remove the touch replay section from `README.md` and qualify the cross-platform claim so it does not promise full touchscreen support.

## 3. Remove Plane's custom touch layer

Suggested route: remove the obsolete policies at their existing owners. Do not add a replacement navigation abstraction, ownership callback, compatibility alias, or dependency.

- [x] In `lib/canvas/editor/canvas_page.dart`, remove touch Select visibility, platform detection, first-touch discovery, and the touch-only toolbar action. Remove any now-unused widget parameters or imports.
- [x] Delete `lib/canvas/editor/browser_touch_observer.dart` and `browser_touch_observer_web.dart` after removing their consumers.
- [x] In `editor_session.dart` and `editor_history.dart`, remove `touchSelectionEnabled`, its tool-choice parameters, snapshot comparisons, and restoration/reset plumbing.
- [x] In `canvas_input.dart`, remove touch-only manual panning, marquee selection, deferred placement, and double-tap insertion branches. Remove dedicated multi-touch takeover bookkeeping that no longer serves a retained behavior.
- [x] Trace raw pointer entry points, element targets, creation tools, and controls so finger input cannot independently start custom canvas edits while Grid handles navigation. Preserve mouse and stylus paths; do not block native UI touch behavior globally.
- [x] In `canvas_view.dart`, remove `_touchNavigationActive`, its session-replacement handoff, and the removed Grid mode/callback arguments. Remove the now-unused `navigationChanged` plumbing from `CanvasInput`.

Keep these shared protections while deleting the touch layer:

- [x] Pointer cancellation and held-pointer blocking for tool changes, dialogs, restoration, and session replacement.
- [x] Lifetime-bound element/control callbacks; old callbacks cannot edit removed or replacement elements.
- [x] Cancellation of unfinished drafts and correct undo grouping for already-applied changes.
- [x] Mouse marquee, modifier/group selection, Space-pan, secondary-click menus, and secondary/middle-button navigation.
- [x] Stylus sampling, drawing, and cancellation.
- [x] Focus priority, clipboard cancellation, resource retention, and persistence error handling.

Touch Select belongs to transient editor/history state, not the saved document. No document-format, library, attachment, or saved-file migration is indicated.

## 4. Update the dependency

- [x] Refresh only the Grid dependency to the reviewed mainline revision and update `pubspec.lock`; do not upgrade unrelated packages.
- [x] Confirm executable source and tests no longer reference the removed enum, constructor arguments, or callback.
- [x] Run analysis to catch stale imports, signatures, previews, and fixtures after the removal.

The confirmed source break is the `LazyCanvas` construction in `canvas_view.dart`. `test/canvas/editor/canvas_history_test.dart` also directly invokes the removed callback. Removing only those references is not sufficient: the app-owned touch policies above must be reconciled too.

## 5. Retire tests for removed behavior

Suggested route: delete the dedicated touch engine coverage, then edit mixed suites selectively. Do not delete a general correctness assertion merely because its fixture uses touch.

| File | Suggested change |
| --- | --- |
| `test/canvas/editor/canvas_touch_test.dart` | Retire the dedicated touch Select, discovery, placement, motion, and takeover suite. Its narrow mouse/stylus toolbar case only asserts that touch Select stays hidden; remove that obsolete assertion and retain any useful general toolbar coverage in the toolbar suite. |
| `test/canvas/editor/canvas_navigation_test.dart` | Keep the first three mouse navigation tests: right/middle drag over controls, right drag in Draw mode, and Space-pan. Delete the custom touch-frame oracle checks, replay matrices, anchoring, coincident-contact, response-budget, and replacement-finger tests. |
| `test/canvas/touch_test_helpers.dart` | Delete once its replay-suite consumers are removed. |
| `test/canvas/editor/canvas_history_test.dart` | Remove the touch Select undo case. Rewrite the test that invokes `onTouchNavigationChanged` to use supported navigation, preserving the assertion that navigation does not split content history. |
| `test/canvas/editor/canvas_input_test.dart` | Remove touch Select, finger double-tap, touch marquee, and custom touch-pan cases/variants. Preserve stale callback/completion tests by using a supported interruption path instead of two-finger takeover. |
| `test/canvas/editor/canvas_selection_test.dart` | Preserve mouse/group/zoom behavior. Replace the touch-dependent cancellation fixture with supported-pointer cancellation so cancellation coverage remains. |
| `test/canvas/editor/canvas_arrange_test.dart` | Remove takeover-dependent portions and unsupported canvas-touch variants. Keep canceled-click behavior, Auto promotion, group targets, ordering, menu behavior, and undo assertions. |

- [x] Review default pointer kinds in retained tests. `TestPointer()` and gestures without an explicit kind can produce touch input; use explicit mouse or stylus input when that is the behavior being tested.
- [x] Keep native UI touch cases where they test media-field focus exit, dropdown behavior, or editor selection rather than the removed canvas policy.
- [x] Keep stylus coverage, including protection against an unrelated finger stealing a stylus stroke where applicable.
- [x] Keep clipboard, document, resource, arrangement, storage, import, attachment, and general history suites.
- [x] Remove `test-touch` from `Makefile`, including its `.PHONY` entry.

Do not rebuild the replay harness around Flutter's default recognizer or weaken its old oracle until it passes. The old oracle tests a contract that is intentionally being retired. Grid already covers its retained basic touch navigation; add a Plane smoke check only if it verifies a retained integration responsibility.

## 6. Adopt bounds-aware culling without redesigning Plane

No concrete Plane regression or required redesign was identified from this change. Culling is Grid's responsibility. Plane supplies geometry and retains resources across unmounting; it should not depend on the exact point at which Grid unmounts an object.

Grid now uses known rotated layout bounds instead of only origins. It retains measured sizes after culling and discovers unknown or empty-size children by origin. Bounds do not include arbitrary shadows or paint overflow.

- [x] Keep Plane's existing child-size, position, and rotation projection in `canvas_view.dart`. It already supplies bounds and synchronizes document/resource geometry changes.
- [x] Keep Grid's new `minHorizontalBuildPadding` default of 200 logical screen pixels per side. Do not set it to zero to preserve obsolete test expectations.
- [x] Keep resource-lifetime and auto-height text tests. If a fixture fails to cull an object, establish that its entire layout bounds are outside the buffered region rather than assuming an offscreen origin is enough.
- [x] Verify that normal geometry updates still reach Grid while an element is culled, including resource-driven media sizing and code title bounds. Change Plane only if a concrete violation is found.

Measurements and limits, not assumed migration failures:

- Plane uses `buildExtentMultiplier: 3.4`; its existing horizontal padding already exceeds the new minimum at canvas widths of about 167 logical pixels or more.
- Auto-height text initially supplies a minimum height that can be smaller than actual layout. Initial discovery and later cached measurements are an existing sizing caveat, not a demonstrated new regression.
- Bounds indexing can retain more objects and use more index references. Extremely large children are outside Grid's stated optimization target; large strokes and arrows may warrant measurement if an actual workload exposes a problem.
- Grid's published profile results are Linux controller/index measurements, not evidence about Plane's Chrome frame rate, glass rendering, or memory use. Do not add a benchmark project or tune buffering without evidence.

## 7. Verify and finish

- [x] Run focused Chrome tests for the changed input, navigation, history, selection, arrangement, and toolbar behavior.
- [x] Run the existing resource-culling and auto-height text checks. Confirm actual unmount/remount behavior and retained resources, not old culling thresholds.
- [x] Run `flutter analyze` and `flutter build web`.
- [ ] Check physical touchpad and stylus interactions in the web app. Automated Chrome pointer tests cover mouse/stylus paths; a browser smoke check covered mouse text creation/editing, dragging, right-click menus, wheel navigation, and keyboard interaction. Physical touchpad/stylus hardware was not available.
- [x] Run the full Chrome test suite once before committing the migration.
- [x] Check that documentation and implemented behavior agree and that removed touch helpers, observer files, parameters, imports, and commands have no remaining consumers.

Browser-dependent test command:

```sh
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome <test-file>
```

## Verification results

- Full `flutter analyze` passed with no findings, and `git diff --check` passed. The web build succeeded with Wasm dry-run warnings from the existing `isolate_contactor` dependency.
- All six VM architecture checks passed.
- The full Chrome run finished with 609 passed, four skipped appearance-flag scenarios, and seven failed fixtures. The failures used touch input to perform canvas edits that now require mouse or stylus input. After correcting those fixtures, all four affected files passed their targeted rerun: 29 passed and the same four appearance-flag skips. All 616 runnable Chrome scenarios were verified across the full run and targeted corrections; the full suite was not repeated.
- The final fixture corrections cover `pen_tool_test.dart`, `code_language_picker_test.dart`, `canvas_file_picker_test.dart`, and `app_test.dart`. Native dropdown touch coverage remains; canvas activation/deactivation uses mouse input. No supported behavior assertion was removed from these four files.
- Font-download timeout messages appeared in the full run, but the font tests passed. No font-loading or network behavior was changed.
- Source review confirmed that `CanvasView._closeContextMenuOnNavigation` still cancels pending quick-text recognition whenever the viewport changes. No replacement touch-ownership callback was introduced.
- Physical device behavior and Chrome rendering performance were not measured.
