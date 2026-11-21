# Notifications

Status: accepted.

## Scope

Notifications are brief feedback about workspace actions or problems. Keep
Settings validation and progress inline, confirmations modal, and detailed
import reports in their existing surfaces. Notifications are not saved, and
there is no notification history or system-level delivery.

## Behavior

- Place compact cards in a generic canvas-chrome widget slot directly below the
  title, left-aligned with it and separated by 12 logical pixels. The slot
  follows title wrapping and keeps cards clear of the toolbar and tool options,
  including in narrow windows. It stays put when the canvas pans or zooms; do
  not use a workspace-root overlay or reserve viewport clearance. Use the
  toolbar's themed surface and typography, a muted status icon, readable text,
  and a close button. Keep routine messages to one line where they fit; wrap
  text rather than clipping it.
- One event gets one card. A new event gets a separate card. If an event is
  already visible, replace its spinner and text in place with its outcome.
  Do not add a second card or slide the card to a new position.
- Show a spinner only if the operation is still running after 300 ms. If it
  finishes sooner, show only the result. Keep visible progress until the
  operation finishes or the user closes the card.
- Auto-dismiss a success or informational result after 4 seconds, or 10 seconds
  if it offers an action. Start counting when the result is visible. Pause
  the timer while the pointer is over the card, focus is inside it, or a
  modal covers the workspace. Fade out without sliding; respect reduced motion.
  Warnings and errors stay until dismissed.
- Closing a progress card hides it without canceling the work. A later success
  stays quiet, even if it had an action. A later warning or error can surface.
  Closing a result only dismisses that result.
- Show at most two cards at once. Queue overflow without displacing visible
  cards. Give queued warnings and errors the next free slot before other
  notices; keep arrival order within each priority. If queued work has
  finished, show its result, not its spinner.
- Notifications don't take focus on arrival, capture Escape, or intercept
  canvas input outside the cards. Close and any action must be accessible by
  keyboard and have accessible names. Announce meaningful changes to screen
  readers, not spinner frames. While a modal covers the workspace, its
  controls take precedence and notifications are not interactive.

### GitHub commit feedback

Start progress after the user submits the commit dialog. Canceling the dialog
shows no notification. Confirmed success shows `Canvas committed to GitHub.`
without an action and auto-dismisses after four seconds. If GitHub confirmed
the commit but the local sync baseline did not save, show both facts in the
existing warning without an action; it stays until dismissed. If the remote
result is uncertain, keep the uncommitted-changes marker and offer **Check
GitHub** with a warning that submitting again may create a duplicate commit.
Never retry automatically.
See the [interaction model](interaction-model.md#github-canvas-transfers) for
the commit workflow.

If a user tries to start another commit, open the canvas picker, import, or export while a commit is in progress, show the informational notification **“Wait for the current commit to finish, then try again.”** Keep it separate from commit progress and follow the existing rules for notifications covered by a modal.
