# Architecture

Status: accepted architecture contract; transfer caller adoption is implemented;
final integration and verification remain pending.

**Saved values describe the canvas. The editor owns changes. Views own rendering
resources. Storage owns durability.**

This architecture defines accepted ownership and allowed dependencies. The
[interaction model](../specs/interaction-model.md) defines product behavior.
Accepted [asynchronous edit ADR 0001](../adr/0001-cancel-unfinished-pastes.md),
[canvas document and media ADR 0002](../adr/0002-separate-documents-and-media.md),
[media link cards ADR 0003](../adr/0003-media-link-cards-without-embeds.md), and
[folder-based transfer ADR 0005](../adr/0005-folder-based-canvas-transfers.md)
record their rationale and consequences. Older notes, research, and migration
records do not override these authorities. Update the relevant contract when an
intentional design decision changes. Remaining transfer integration and
verification are tracked in the [active plan](../plans/folder-based-canvas-transfers.md).

## Responsibilities

- [Ownership and dependencies](ownership.md): project structure, boundaries,
  and shared design rules.
- [Editor lifecycles](editor-lifecycles.md): document editing, input, history,
  rendering resources, and asynchronous edit workflows.
- [Persistence](persistence.md): library ownership, saving, and import/restore.
- [UI](ui.md): theme, presentation, shared components, and UI dependencies.

## Dependency direction

App composition connects feature entry points. Document values and geometry
remain independent of presentation, storage implementations, and browser APIs.
Editor logic uses narrow I/O contracts; presentation requests editor operations
and never writes saved fields. The library does not import the editor, and
app-wide UI does not import features. The detailed owner table is in
[ownership](ownership.md).
