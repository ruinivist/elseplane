# Notifications implementation plan

Status: active.

## Scope

Implement the [notification spec](../specs/notifications.md) first for GitHub
commits and Workspace save/load errors. Verify the pilot before migrating
other snackbars. No dependencies, saved notification state, or changes to
transfer and persistence rules.

## Pilot

- [x] Add a shared card and host in `lib/ui/common/`. Use existing surfaces and
  theme values. Give the host ownership of event identities, visible and queued
  cards, and timers. Provide two reporting paths: a one-off result for an
  already-known outcome and a progress handle that updates that event to a
  result. The host only presents feedback; it does not run operations.
- [x] Place the host in a generic canvas-chrome widget slot directly below the
  title, left-aligned with it and separated by 12 logical pixels. Keep it inside
  the Workspace route so dialogs remain above it and route state pauses expiry
  and suppresses announcements while covered. Follow title wrapping and avoid
  toolbar and tool options without a workspace-root overlay or reserved
  viewport clearance.
- [x] Replace the commit snackbar in `lib/github/github_sync.dart` with the
  shared reporting path. Workspace supplies it; GitHub owns outcome copy and
  the **Check GitHub** action for an uncertain result. Confirmed success has no
  action; baseline-save warnings remain persistent. After dialog submission,
  keep one progress handle through encoding, the remote write, and the local
  baseline save. Route a failure before submission to a one-off error; do not
  show progress for a canceled dialog. Preserve the transfer interlock,
  sanitized errors, and default-branch handling. Ignore late completions after
  disposal.
- [x] Replace only the Workspace load and save error snackbars in the pilot.
  Keep existing save-error detection and avoid reposting the same outstanding
  save failure. Leave export and other feedback alone until after the pilot.

## Verification and rollout

- [x] Add a shared widget preview and focused tests under `test/ui/`. Cover
  fast completion without a spinner, in-place results, distinct events,
  overflow priority, timer pauses, and dismissal without cancellation. Check
  that hidden work stays quiet on success but surfaces a warning or failure.
- [x] Extend `test/app/github_workspace_test.dart` and
  `test/app/workspace_loading_test.dart` for the pilot. Verify cancel, confirmed
  success without an action and its four-second expiry, baseline-save warning
  without an action, uncertain result and **Check GitHub** link, and Workspace
  load/save feedback. Keep existing checks on the underlying operations.
- [x] Run focused Chrome tests, `flutter analyze`, and `flutter build web`.
- [x] Run the full Chrome suite before committing implementation.
- [ ] Check the running web app with dark and light surfaces, short and narrow
  viewports, open tool options and dialogs, and keyboard navigation. Confirm
  canvas gestures still work outside the cards.
- [x] Recheck the pilot with the Chrome widget tests and migrate the remaining
  brief snackbars. Keep Settings feedback inline and leave confirmations
  and detailed import reports in their existing surfaces.
- [x] Add a VM architecture test to prevent Material snackbars from returning
  in app source: `flutter test test/architecture/workspace_feedback_test.dart`.

Screen reader testing is deferred to the [backlog](../backlog.md#improvements)
and does not block the pilot.
