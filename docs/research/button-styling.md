# Button styling in Settings, the explorer, and GitHub

Reviewed: 2026-11-23

## Asks and outcomes

| Ask | Outcome |
| --- | --- |
| Find out which buttons already share styling. | Ordinary text and icon buttons already inherit the Starless theme. Keep that approach and add shared outlined, filled, and compact icon styles there. No generic button wrapper or added elevation. |
| Make Settings actions easier to recognize. | Give the three Data actions equal outlined buttons, use the existing default border for Background, Surface style, and Theme selects, and underline the About links while keeping their external-link arrows. Leave Settings tabs unchanged. |
| Make the canvas explorer header less cramped. | Keep all four actions quiet. Use 32 × 32 targets with 18 px icons, add 6 px above the first file row, and use the same compact Close treatment in the explorer, Settings, and the GitHub import dialog. |
| Compare the Sync, Import, and Commit flows. | Fill Connect GitHub, Import from GitHub, Import canvases, and Commit inside its dialog. Keep secondary actions and the canvas-title Commit action quiet. |
| Remove focus outlines that appear without keyboard navigation in GitHub import. | Remove automatic focus from Cancel and Done, including the current requirement to focus Cancel on confirmation. Keep normal keyboard traversal and visible focus when users tab to a control. Update the [GitHub Sync UX specification](../specs/github-sync-ux.md#import) with the implementation. |
| Balance the Saving dialog and notification spacing. | Keep disabled Close in the same header slot, add bottom breathing room below the Saving row, and increase notification left padding from 8 to 12 px without moving the dismiss button. |

## Screenshot evidence

Before is on the left and the inline prototype is on the right. These are desktop dark/glass captures from the running app. Appearance was temporarily visible in both versions. The GitHub pass contains 25 pairs made with fake responses and in-memory storage, without signing in or making real repository writes.

- [Settings and canvas explorer](../artifacts/button-styling/settings-and-explorer.png)
- Sync: [connection and repository setup](../artifacts/button-styling/sync-1.png), [repository picker and access management](../artifacts/button-styling/sync-2.png), [branch change and return to Sync](../artifacts/button-styling/sync-3.png)
- Import: [Preparing, Confirm, Saving, and success](../artifacts/button-styling/import-1.png), [nothing to import](../artifacts/button-styling/import-2.png)
- Commit: [title, dialog, validation, cancel, and progress](../artifacts/button-styling/commit-1.png), [success and failure](../artifacts/button-styling/commit-2.png)

The boards don’t show import preparation or save failure, commit baseline-save failure, or an unconfirmed commit. A sample canvas note overlaps the title in some Commit captures; that overlap is not part of the proposed style. The prototype edits were removed. The final focus and spacing adjustments were selected after the captures and are not shown.
