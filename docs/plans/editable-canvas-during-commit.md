# Keep the canvas editable during GitHub commits

Status: active

## Scope

Implement the [GitHub transfer behavior](../specs/interaction-model.md#github-canvas-transfers) and [blocked-action feedback](../specs/notifications.md#github-commit-feedback). Keep the current snapshot, autosave, and GitHub transport. Switching canvases and other transfers remain out of scope while a commit runs.

## Design

1. In `Workspace`, separate the lifetime of the shared transfer interlock from the canvas input block. Only GitHub commit can lift the input block early; local transfers, other GitHub operations, and the canvas picker keep their existing lifecycle. Keep cleanup in the existing `finally` path, including on dialog cancel, preparation failure, remote failure, or an uncertain outcome.
2. In `GitHubSync.commit`, keep the existing flush and capture before the message dialog. After submission, build the `TransferTree` and baseline from the capture as today. Signal `Workspace` to restore input once the package and baseline are ready, before calling GitHub. Hold the interlock through the result and any local baseline save. Save only the baseline for the captured canvas ID through the existing library save queue; do not write the captured document back over newer edits.
3. Keep the Commit action, canvas picker (title and keyboard shortcut), and normally eligible local import, GitHub import, and export actions reachable during the network wait. Reject them at their existing entry points before opening pickers, changing state, or starting I/O. Use the existing notification controller for the informational notice and leave commit progress untouched. Other Sync controls retain their busy state and inline status; do not add a notification overlay to Settings or change its modal behavior.

## Verification

- Extend `test/app/github_workspace_test.dart` with a controllable commit response. While it is pending, verify pan and zoom work, make a canvas edit, and verify the outbound package still contains the original version. After confirmed success, verify the edit survives autosave and the `*` remains; confirm an unchanged canvas still clears its marker.
- During the same wait, exercise the second Commit, canvas picker by title and shortcut, and import/export attempts. Verify feedback, no second request or picker, and no deferred action after the commit finishes. Verify the notice respects modal coverage for Settings actions.
- Cover cancellation and preparation failure before the input block lifts, and remote failure after it lifts. Verify the editor and transfer actions recover, the marker stays, and existing failure feedback is preserved.
- Run focused Chrome tests, `flutter analyze`, and `flutter build web`. Run the full Chrome suite before committing code.
