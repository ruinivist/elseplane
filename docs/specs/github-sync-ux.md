# GitHub sync UX

Status: accepted

## Sync settings

When GitHub is configured, **Sync** appears between **Canvas** and **About** in Settings. Show **Connect GitHub** when signed out. Authorization returns to Sync, which shows the account and repository controls once verified.

```text
Canvas  | GitHub
[Sync]  | Connected as @yourname                  [ Log out ]
About   |
        | Repository
        | [ yourname/canvases v ] [ refresh icon ]
        | Private / Default branch: main
        |
        | [ Import from GitHub ]   Manage GitHub access >
```

- Use a searchable dropdown with **Choose repository** as its empty state. Selecting a repository explicitly confirms the choice. Save it after validation. Show its visibility and default branch as plain text below the dropdown.
- Put an icon-only **Refresh repositories** button next to the dropdown. Use the label for its tooltip and accessible name. Show refresh progress and errors inline.
- **Log out** ends the Elseplane session directly and returns to **Connect GitHub**. Keep the saved repository for the same account when it reconnects. Show a retry inline if logout fails.
- **Manage GitHub access** opens GitHub in a new tab. Show installation choices inline, including the option to install on another account. Keep connection and repository setup in Sync without opening another dialog over Settings.
- **Import from GitHub** uses the selected repository. Selecting a repository
  does not start an import; the user starts it with this action. Import and
  Commit use the repository's default branch. If the default branch changes,
  ask the user to refresh and reselect the repository before transferring.

## Import

**Import from GitHub** opens one dialog over Sync. Use the same dialog whether
or not any local canvases would be replaced. Clicking outside never dismisses
it.

```text
1. PREPARING — cancellable
+------------------------------------------------------+
| Import from GitHub                              [X]  |
| owner/canvases · main                                |
|                                                      |
| (spinner) Preparing import…                          |
|                                           [ Cancel ] |
+------------------------------------------------------+

2. CONFIRM — cancellable
+------------------------------------------------------+
| Import from GitHub                              [X]  |
| owner/canvases · main                                |
|                                                      |
| 3 canvases ready to import.                          |
|                                                      |
| Will replace 1 local canvas:                         |
|   Untitled.canvas.json                               |
| Shared images may also change in other canvases.     |
|                       [ Cancel ]  [ Import canvases ]|
+------------------------------------------------------+

3. SAVING — not cancellable
+------------------------------------------------------+
| Import from GitHub                     [X disabled]  |
| owner/canvases · main                                |
|                                                      |
| (spinner) Saving canvases…                           |
+------------------------------------------------------+

4. RESULT — dismissible
+------------------------------------------------------+
| Import from GitHub                              [X]  |
|                                                      |
| Imported 3 canvases.                                 |
|                                             [ Done ] |
+------------------------------------------------------+
```

1. **Preparing.** Show the selected repository and branch, a spinner with
   **Preparing import…**, and **Cancel**. Cancel, Close, or Escape returns to
   Sync immediately. Canceling stops further import reads and leaves local
   canvases and images untouched. An in-flight request may finish, but its
   result is ignored and must not block the workspace or affect a later import.
2. **Confirm.** Show how many canvases are ready to import. If any local canvases
   would be replaced, show their count and paths and warn that shared images
   may also change in other canvases. Let long lists scroll without moving the
   buttons. Focus **Cancel** initially. Cancel, Close, or Escape returns to Sync
   without import writes. **Import canvases** starts saving, with or without
   replacements.
3. **Saving.** Keep the dialog open. Show a spinner with **Saving canvases…**,
   remove **Cancel**, and visibly disable Close. Escape does nothing. The user
   cannot dismiss the dialog once saving starts.
4. **Result.** Show **Imported 1 canvas.** or **Imported N canvases.** on success,
   without a replacement count or list. If nothing can be imported or
   preparation fails, go straight to the result without confirmation. On
   failure, explain what failed and warn if shared images may already have
   changed even though canvases were not saved. **Done**, Close, or Escape
   returns to Sync.

This flow applies to GitHub import only. Local import follows the
[canvas file interaction model](interaction-model.md).

## Uncommitted changes

Append `*` to the current canvas title when the signed-in account has a selected repository and the canvas differs from its baseline or has no baseline for that account, repository, and branch. This includes existing canvases on first connection. The title's accessible label includes **Uncommitted changes**.

The app compares the canvas path, canonical document, and referenced attachment contents using local data. Successful GitHub imports establish baselines for the imported versions. Local autosave keeps the marker visible while the canvas differs from its baseline. A confirmed commit clears it when the commit includes the current changes. Keep the marker visible if you cancel, the commit fails or remains unconfirmed, or you edit the canvas after the snapshot is taken.

## Commit the current canvas

```text
At rest       some new*
Hover/focus   some new*  [ Commit ]
```

- Clicking or tapping the title, including the asterisk and the padding before the button, opens the canvas explorer. If the title is clipped, its tooltip shows the full path and sits clear of the title and **Commit**.
- Hover over the title or move keyboard focus into the title area to reveal **Commit**. The button appears beside the title when it fits and directly below when it needs its own row. The title stays in place and the button stays visible while the pointer or focus moves onto it.
- On touch-only browsers, show **Commit** whenever committing is available. **Commit** opens the dialog with the selected repository and branch and asks for a commit message before publishing the current canvas.

Confirmed commits show a success notification without an action. If saving the
local baseline fails, show both outcomes in a persistent warning without
retrying the remote write. An uncertain result shows **Check GitHub** and warns
that submitting again may create a duplicate commit.

Repository eligibility and commit behavior follow the [GitHub canvas transfer contract](interaction-model.md#github-canvas-transfers).
