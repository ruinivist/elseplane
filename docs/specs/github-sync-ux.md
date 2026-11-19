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
        | [ Import from GitHub... ]   Manage GitHub access >
```

- Use a searchable dropdown with **Choose repository** as its empty state. Selecting a repository explicitly confirms the choice. Save it after validation. Show its visibility and default branch as plain text below the dropdown.
- Put an icon-only **Refresh repositories** button next to the dropdown. Use the label for its tooltip and accessible name. Show refresh progress and errors inline.
- **Log out** ends the Elseplane session directly and returns to **Connect GitHub**. Keep the saved repository for the same account when it reconnects. Show a retry inline if logout fails.
- **Manage GitHub access** opens GitHub in a new tab. Show installation choices inline, including the option to install on another account. Keep connection and repository setup in Sync without opening another dialog over Settings.
- **Import from GitHub…** uses the selected repository. Import and Commit use its default branch. If the default branch changes, ask the user to refresh and reselect the repository before transferring.

## First-time import

On the first GitHub setup, once the user selects a repository they can import from, show this prompt inline in Sync.

```text
Import canvases from repo?
[ Import from GitHub... ]   [ Skip ]
```

**Import from GitHub…** and **Skip** both dismiss the first-time prompt. Regular import remains available. When paths collide, show their paths and the shared-image warning inline and wait for confirmation. Canceling or dismissing the review leaves local data untouched. Show the result and affected paths in Sync.

## Uncommitted changes

Append `*` to the current canvas title when the signed-in account has a selected repository and the canvas differs from its baseline or has no baseline for that account, repository, and branch. This includes existing canvases on first connection. The marker's tooltip and accessible label say **Uncommitted changes**.

The app compares the canvas path, canonical document, and referenced attachment contents using local data. Successful GitHub imports establish baselines for the imported versions. Local autosave keeps the marker visible while the canvas differs from its baseline. A confirmed commit clears it when the commit includes the current changes. Keep the marker visible if you cancel, the commit fails or remains unconfirmed, or you edit the canvas after the snapshot is taken.

## Commit the current canvas

```text
At rest       some new*
Hover/focus   some new*  [ Commit... ]
```

- Hover over the title or move keyboard focus into the title area to reveal a small **Commit…** button immediately to the right of the marker. Keep the title in place and the button visible while the pointer or focus moves onto it.
- Clicking the title opens the canvas explorer. The marked title exposes its folder path in a tooltip. Tapping the separate marker on a touch screen opens the commit dialog when write access is verified.
- **Commit…** opens the existing commit dialog. The dialog shows the selected repository and branch and asks for a commit message before publishing the current canvas.

Confirmed commits show **View commit** on the canvas. If saving the local baseline fails, show both outcomes without retrying the remote write. An uncertain result shows **Check GitHub** and warns that submitting again may create a duplicate commit.

Repository eligibility and commit behavior follow the [GitHub canvas transfer contract](interaction-model.md#github-canvas-transfers).
