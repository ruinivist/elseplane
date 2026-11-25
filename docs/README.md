# Documentation

This is the sole map and writing guide for project documentation. Read it first,
then read the authority relevant to the work. Do not create a separate
`documentation.md` or empty category folders.

## Map and authority

- [Architecture](arch/README.md) is the accepted ownership and
  dependency contract. Its detail is split into
  [ownership](arch/ownership.md), [editor lifecycles](arch/editor-lifecycles.md),
  [persistence](arch/persistence.md), and [UI](arch/ui.md).
- [Interaction model](specs/interaction-model.md) is the accepted product
  behavior contract. The accepted [asynchronous edit decision](adr/0001-cancel-unfinished-pastes.md),
  [canvas document and media decision](adr/0002-separate-documents-and-media.md),
  [media link cards decision](adr/0003-media-link-cards-without-embeds.md), and
  [folder-based transfer decision](adr/0005-folder-based-canvas-transfers.md)
  record their rationale and consequences. ADR 0002 remains accepted for
  document/media separation; its transfer and replacement-import portions are
  superseded by ADR 0005.
- [GitHub sync UX](specs/github-sync-ux.md) covers Sync settings and
  the canvas title's uncommitted-changes marker and commit action.
- [Notifications](specs/notifications.md) defines workspace feedback cards.
  The [implementation plan](plans/notifications.md) covers the pilot and rollout.
- **Deferred:** [canvas input delegation ADR 0004](adr/0004-delegate-canvas-input-behavior.md)
  and its [migration plan](plans/input-delegation.md). They remain proposals;
  accepted architecture and behavior remain authoritative until the ADR is
  accepted.
- **Accepted target; caller adoption implemented; final integration pending:** [folder-based canvas transfer
  specification](specs/folder-based-canvas-transfers.md), [architecture
  design](arch/folder-based-canvas-transfers-design.md), and [ADR
  0005](adr/0005-folder-based-canvas-transfers.md). The aligned interaction,
  persistence, ownership, and editor-lifecycle contracts govern the target.
  Parent-aware caller adoption is implemented. The [active plan](plans/folder-based-canvas-transfers.md)
  tracks final integration, automated checks, and required reviews.
- **Accepted, storage foundation only:** [root-relative attachment path
  specification](specs/attachment-paths.md) and [ADR 0006](adr/0006-path-aware-attachment-store.md).
  These remain the byte-store contract; parent-aware caller adoption and import
  publication are accepted by ADR 0005 and implemented.
- **Implemented:** [ADR 0007: store canvases
  individually in IndexedDB](adr/0007-store-canvases-individually-in-indexeddb.md).
  The [browser canvas persistence specification](specs/browser-canvas-persistence.md)
  defines local save and load behavior. The [completed plan](archive/browser-canvas-persistence.md)
  defines the architecture and worker split.
- **Declined:** [ADR 0008: simplify glass at overview zoom](adr/0008-simplify-glass-at-overview-zoom.md).
  Replaced by [ADR 0010: skip blur on clear canvas backdrops](adr/0010-skip-blur-on-clear-canvas-backdrops.md).
- **Implemented:** the
  [selective canvas glass specification](specs/selective-canvas-glass.md)
  defines the card-only policy. The [completed plan](archive/selective-canvas-glass.md)
  links validation of the initial implementation.
- **Proposed:** [ADR 0009: speed up GitHub canvas transfers](adr/0009-speed-up-github-canvas-transfers.md),
  with a [draft specification](specs/github-transfer-performance.md), a
  [commit blob reuse plan](plans/github-commit-blob-reuse.md), and a
  [parallel blob import plan](plans/github-parallel-blob-import.md).
- [Backlog](backlog.md) contains reported defects, proposals, and open
  verification. Entries are not accepted behavior or architecture.
- [Plans](plans/) track active work and its checks; they do not
  override architecture or accepted specifications. Completed plans belong in
  [archive](archive/).
  The [editable canvas during commit plan](plans/editable-canvas-during-commit.md)
  tracks separating canvas input from the transfer interlock.
  The [active GitHub repository selection plan](plans/github-repository-selection.md)
  tracks GitHub App authorization, repository selection, and empty-repository
  rejection; live discovery and integration checks remain pending.
- [Playbooks](playbooks/) contain practical setup and development commands,
  including the [local GitHub App setup](playbooks/github-setup.md).
- [Research](research/) contains time-bound investigations and source evidence;
  findings are not confirmed defects or requirements unless accepted elsewhere.
  [Canvas pan performance](research/canvas-pan-performance.md) records the
  low-zoom benchmarks and remaining rendering suspects.
  [Button styling](research/button-styling.md) records the Settings, explorer,
  and GitHub visual comparisons and the selected changes.
- [Artifacts](artifacts/) holds screenshot boards linked from research entries.
- [Archive](archive/) preserves superseded notes and completed work for history.

## Required reading

- Every task: this map and any relevant nested `AGENTS.md`.
- Structural or ownership changes: architecture overview and affected detail
  documents.
- Interaction changes: accepted interaction model and relevant ADRs.
- Migration work: architecture, behavior authority, and the active plan.
- Documentation changes: this guide and the document being changed.

When authorities conflict, accepted architecture and specifications govern;
plans, research, backlog entries, and archived notes cannot silently change
them. Update the authority when an accepted contract changes.

## Naming and lifecycle

Use lowercase kebab-case filenames, except `README.md` and `AGENTS.md`. Keep
links and local asset references relative to their owning document. Keep
supporting files beside their research or group screenshot boards by topic
under `artifacts/`. Update references when names or locations change. Create a
file or folder only when it has content and a current purpose.

Move ideas to the backlog for triage. Promote accepted behavior or ownership
rules to a specification or architecture document, recording consequential
choices as ADRs. Keep active checklists in plans; move completed histories to
the archive. Keep dated or revision-specific evidence in research and link
actionable follow-up from the backlog. Remove finished backlog entries rather
than preserving duplicate checklists.

## Small document templates

Documentation effort follows ambiguity and risk. Not every change needs a spec,
plan, or ADR. For substantial changes, include a design section in the plan when
needed; a separate design document is not required. Use only applicable headings;
omit empty sections.

**Architecture**

```md
# <responsibility>

## Ownership
## Boundaries
## Lifecycle or correctness rules
```

**Specification**

```md
# <behavior>

Status: accepted

## Scope
## Acceptance criteria
## Behavior
```

**ADR**

```md
# <decision>

Status: proposed | accepted | superseded
Date: YYYY-MM-DD

## Context
## Decision
## Alternatives
## Consequences
```

**Plan**

```md
# <migration>

Status: active | complete
## Scope
## Checklist
## Verification
```

**Research**

```md
# <question>

Reviewed: <date or revision>
## Scope and method
## Findings
## Limits
```

**Playbook**

```md
# <task>

## Prerequisites
## Commands
```

**Backlog entry**

Keep three sections in `backlog.md`: `Bugs` for broken behavior, `Improvements`
for proposed features, UX changes, refactoring, and maintenance, and
`Verification` for specific unanswered questions or outstanding checks. Order
entries by priority within each section. Bugs must distinguish `reported` from
`confirmed`; confirmation requires reproducible evidence against the accepted
contract. Improvements are proposals, not requirements. Verification entries
state what to check and what resolves the question.

Use a short entry with the problem, optional evidence, and next step. Add a
stable ID only when another document needs to reference it. Link to active
plans instead of duplicating their checklists; small fixes need no plan. Remove
completed entries after capturing any lasting conclusions in their proper home.

```md
- **<title>:** <problem>. Evidence: <optional>. Next: <action>.
```
