# Architecture

Status: current accepted implementation contract.

**Saved values describe the canvas. The editor owns changes. Views own rendering
resources. Storage owns durability.**

This architecture defines implemented ownership and allowed dependencies. The
[interaction model](../specs/interaction-model.md) defines product behavior;
the accepted [paste cancellation ADR](../adr/0001-cancel-unfinished-pastes.md),
[canvas document and media ADR](../adr/0002-separate-documents-and-media.md), and
[media link cards ADR](../adr/0003-media-link-cards-without-embeds.md) record
their rationale and consequences. Older notes, research, and migration
records do not override these authorities. Update the relevant contract when an
intentional design decision changes.

## Responsibilities

- [Ownership and dependencies](ownership.md): project structure, boundaries,
  and shared design rules.
- [Editor lifecycles](editor-lifecycles.md): document editing, input, history,
  rendering resources, and cancellation.
- [Persistence](persistence.md): library ownership, saving, and import/restore.
- [UI](ui.md): theme, presentation, shared components, and UI dependencies.

## Dependency direction

App composition connects feature entry points. Document values and geometry
remain independent of presentation, storage implementations, and browser APIs.
Editor logic uses narrow I/O contracts; presentation requests editor operations
and never writes saved fields. The library does not import the editor, and
app-wide UI does not import features. The detailed owner table is in
[ownership](ownership.md).
