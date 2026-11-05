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

## Verification

- **Physical touchpad and stylus checks remain open.** Implementation and
  automated checks are complete; perform the remaining hardware checks in the
  [active Grid migration plan](plans/grid-migration.md#7-verify-and-finish).
- **UI consistency audit needs browser confirmation.** Its seven findings are
  source-review candidates, not runtime-verified defects; follow the linked
  [audit](research/ui-consistency-audit.md) when validating them.
