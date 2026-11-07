# Documentation

This is the sole map and writing guide for project documentation. Read it first,
then read the authority relevant to the work. Do not create a separate
`documentation.md` or empty category folders.

## Map and authority

- [Architecture](arch/README.md) is the accepted implementation ownership and
  dependency contract. Its detail is split into
  [ownership](arch/ownership.md), [editor lifecycles](arch/editor-lifecycles.md),
  [persistence](arch/persistence.md), and [UI](arch/ui.md).
- [Interaction model](specs/interaction-model.md) is the accepted product
  behavior contract. The accepted [paste cancellation decision](adr/0001-cancel-unfinished-pastes.md),
  [canvas document and media decision](adr/0002-separate-documents-and-media.md),
  and [media link cards decision](adr/0003-media-link-cards-without-embeds.md)
  record their rationale and consequences.
- [Backlog](backlog.md) contains reported defects, proposals, and open
  verification. Entries are not accepted behavior or architecture.
- [Plans](plans/) track active work and its checks; they do not
  override architecture or accepted specifications. Completed plans belong in
  [archive](archive/).
- [Playbooks](playbooks/) contain practical setup and development commands.
- [Research](research/) contains time-bound investigations and source evidence;
  findings are not confirmed defects or requirements unless accepted elsewhere.
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
images, HTML comparisons, and launchers beside their research and update every
reference when names or locations change. Create a file or folder only when it
has content and a current purpose.

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
