# Backlog

Bug and improvement entries preserve reports and proposals; none is a confirmed
defect or an accepted requirement. Verification entries track open checks.
Validate each reported problem and intended behavior before implementation.
Order is by likely user impact, with unverified reports kept distinct from
confirmed behavior.

## Bugs

- **Audit candidate — dropdown trigger focus:** The source audit reports that
  closed dropdowns lack visible keyboard-focus styling. Runtime behavior was
  not checked; reproduce with keyboard focus before changing the style.
  [Audit details](research/ui-consistency-audit.md#1-dropdown-triggers-lose-keyboard-focus-styling).
- **Audit candidate — Arrange and Delete controls:** The source audit reports
  missing shared feedback and keyboard access. Verify current controls in the
  browser before proposing a fix.
  [Audit details](research/ui-consistency-audit.md#2-arrange-and-delete-bypass-themed-buttons-entirely).
- **Reported — arrow drawing over text:** An old issue says a drag starting
  over text does not draw an arrow. Reproduce and confirm expected behavior.
- **Reported — image click-to-delete:** An old idea says clicking an image and
  then Delete does not work. Reproduce with current selection behavior.
- **Reported — multi-select while holding the primary button:** An old note
  flags this case without describing expected behavior. Reproduce and specify
  the intended result.
- **Reported — drag selection consistency:** An old idea says drag selection
  is inconsistent. Capture a reproducible case before deciding whether it is a
  defect.
- **Reported — text preview sizing:** An old issue says preview sizing differs
  substantially from edit-mode sizing. Compare both modes and identify the
  expected dimensions.
- **Audit candidate — file-row feedback:** The source audit reports that row
  backgrounds cover hover, focus, and pressed feedback. Verify in the browser.
  [Audit details](research/ui-consistency-audit.md#3-the-current-file-row-covers-its-own-interaction-feedback).
- **Audit candidate — dropdown option overlays:** The source audit reports an
  extra Flutter overlay tint. Confirm rendered behavior before changing it.
  [Audit details](research/ui-consistency-audit.md#4-dropdown-options-receive-an-extra-flutter-overlay).
- **Audit candidate — selected swatch focus border:** The source audit reports
  that selection styling can replace focus borders. Verify keyboard focus and
  selection together.
  [Audit details](research/ui-consistency-audit.md#5-selection-borders-override-keyboard-focus-borders).
- **Audit candidate — title and Settings navigation states:** The source audit
  reports partial button-state styling. Verify focus and press states in the
  browser.
  [Audit details](research/ui-consistency-audit.md#6-canvas-title-and-settings-navigation-recreate-partial-button-states).

## Improvements

- **File switching:** More comprehensive file switching support was requested;
  identify the missing workflow before extending it.
- **Responsive layout:** An old idea says the app is not responsive. Define
  supported viewport sizes and reproduce the layout gap.
- **Drawing performance:** An old TODO reports drawing performance issues.
  Profile a representative workload before optimizing.
- **File organization and full export:** An old idea requests web-only folder
  and multi-file organization with full export. Compare the current library and
  backup behavior with the remaining need.
- **Text editing boundary:** An old idea requests a visible boundary while
  editing text. Confirm the intended visual behavior.
- **Text and image tool controls:** Old ideas request different text-handle
  spacing and icon sizing, adjusted text sizing for image creation, and moving
  text options out of the current small handler setting. Specify the affected
  controls and desired consistency.
- **Audit candidate — smooth pointer scrolling:** The source audit reports that
  some settings, dialog, and title panels lack the shared smooth wheel-scroll
  behavior. Verify the current panels and priority before changing them.
  [Audit details](research/ui-consistency-audit.md#7-some-panels-omit-the-shared-smooth-pointer-scrolling).
- **Zoom and tool scale:** An old idea requests a zoom indicator, a sensible
  default zoom, and tool sizing that works at that zoom. Define the use case
  before changing defaults.
- **Shape fill:** A superseded interaction note requests a fill option. Check
  current shape options and product intent before treating this as missing.
- **Media playback:** The root TODO requests better video support. Define the
  required media workflows.
- **Language-server integration:** The root TODO requests LSP integration.
  Define language and editing scope first.
- **Self-hosting:** The root README proposed a self-hosted Docker image and
  sharing. Define deployment and sharing requirements.
- **Extensions:** An old idea requests extensions without a specified use case.
- **Sticky Arrow shortcut:** An old idea asks for holding `A` to remain in
  Arrow mode instead of one-shot placement. This differs from current behavior;
  treat it as a proposal, not a requirement.
- **Deferred — transfer entry count and depth:** Many zero-byte files or deeply
  nested folders may consume CPU and memory despite byte caps. No entry-count or
  depth limit is currently implemented or required; this is not a current
  blocker. Next: reevaluate realistic inputs and limits before expanding
  workloads. See [transfer tree
  adapter rules](arch/folder-based-canvas-transfers-design.md#tree-adapters-and-path-rules)
  and [failure boundaries](specs/folder-based-canvas-transfers.md#validation-and-failure-boundaries).
- **Deferred — moving a canvas during pending image work:** Moving a canvas in
  the file tree, or moving or renaming a containing folder, while an upload or
  attachment-backed paste is pending can leave a broken image reference. Bytes
  stay at the captured old-folder key; the late relative reference resolves in
  the new folder. The current [async-edit policy](arch/editor-lifecycles.md)
  deliberately keeps captured keys and allows late publication. Retain that
  policy for now; frequency is unmeasured. Next: decide whether a directory
  change should suppress late attachment-backed edits before changing the
  contract and tests.
- **Deferred — debug Demo image collision:** Demo creation can replace existing
  bytes at its fixed attachment key. This affects debug builds only and does not
  block release. If addressed later, preserve existing image bytes. Tests should
  not require overwriting them or redundant writes.
- **Deferred — late edit during overwrite publication:** An edit accepted while
  overwrite metadata save is awaited can be discarded after successful
  publication, leaving the controller clean. This is an unresolved race, not an
  intended loss. Next: decide the race policy before changing the contract or
  code and adding a desired-outcome regression.

- **Deferred — screen reader support:** Elseplane has not been tested with a
  screen reader, and end-to-end support is not a current priority. When
  prioritized, test the main workflows, including notification announcements,
  and fix the gaps found. This does not block the notification pilot.

## Verification

- **Nested-layout browser acceptance remains open.** Manually clear this app's
  browser data, then complete the live acceptance checks in the [active
  transfer plan](plans/folder-based-canvas-transfers.md#verification-and-completion).
- **Authenticated GitHub acceptance remains open.** Mocked transport tests do
  not establish live OAuth, repository import, or commit behavior; perform the
  plan's live checks only with available credentials, suitable repositories,
  and permission ([active transfer plan](plans/folder-based-canvas-transfers.md#verification-and-completion)).
- **Physical touchpad and stylus checks remain open.** Implementation and
  automated checks are complete; perform the remaining hardware checks in the
  [active Grid migration plan](plans/grid-migration.md#7-verify-and-finish).
- **UI consistency audit needs browser confirmation.** Its seven findings are
  source-review candidates, not runtime-verified defects; follow the linked
  [audit](research/ui-consistency-audit.md) when validating them.
