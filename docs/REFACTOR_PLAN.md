# Refactor roadmap

Implement the [target architecture](ARCHITECTURE.md) in the order below. Each stage must leave a runnable web app and remove the superseded implementation. This roadmap is migration work; the architecture document holds the lasting rules.

## Baseline and constraints

The source review found ownership problems across four areas:

- `canvas_page.dart` combines input, history, selection, rendering integration, clipboard, file operations, and saving.
- Document definitions import background rendering, syntax highlighting, and font-loading definitions.
- Mutable element models combine saved content, interaction state, Flutter resources, and asynchronous work.
- Tool libraries use shared-private `part` files, and production controls repeat styles despite preview-only shared buttons.

Preserve the [interaction model](Interaction%20model.md), including tool history, per-object Auto arrangement, independent activation/selection/editing, touch navigation, and focused editors' local undo. Retain existing element types, library hierarchy, clipboard workflows, and project/backup formats during structural migration unless an explicit format change is necessary. Backward compatibility with historical versions is not required; unreadable data must still fail visibly without being overwritten.

Keep current dependencies and browser storage initially. Shared code must isolate browser APIs; native storage implementation and non-web verification are separate work. Self-hosting, collaboration, extensions, LSP, and additional media types do not belong to this refactor.

## 1. Establish the architectural contract

- Publish the short constitution and link it and this roadmap from root `AGENTS.md`.
- Clearly distinguish target ownership from the current implementation.
- Treat the interaction model as the behavioral authority; older notes do not override it.

**Exit:** contributors can locate the owner of a new responsibility and identify its allowed dependencies. No application behavior changes in this documentation stage.

## 2. Establish document and geometry boundaries

- Introduce immutable document and element values with immutable collections. Keep sealed element variants together and retain strict serialization validation.
- Move saved background/language enums into the document. Move their rendering/highlighting mappings to presentation. Separate saved font names from font catalog loading.
- Use native graphics values consistently in memory. Keep wire-format and hex-input conversion at their boundaries.
- Extract reusable path, bounds, hit-test, and transform calculations into `canvas/geometry/`. Keep UI measurements and creation defaults with their actual owners.
- Update current models, tools, transfer codecs, clipboard handling, generated serializers, demo data, fixtures, and tests together. Existing model setters can replace immutable values while their mutation ownership migrates in stage 4.

**Exit:** the document imports no presentation or concrete storage. Round trips and invalid-input behavior remain correct. No caller can mutate a published document or its nested collections.

## 3. Separate library durability from widgets

- Move library rules and file UI into `library/`; move attachment contracts and browser storage into `attachments/`.
- Establish `LibraryController` as the library owner and single persistence-queue owner. Make `LibraryStore` an injectable snapshot read/write contract, without a mutable public library.
- Capture file identity, revision, and immutable content for every save. Keep failures visible and preserve dirty state until its corresponding revision is durable.
- Move create, rename, move, delete, import, export, backup, and restore orchestration out of canvas/file-picker widgets. Widgets own inline drafts, navigation, focus, and confirmations.
- Use the staged import protocol in the constitution. Preserve path, byte-size, archive-entry, image, and attachment-reference validation. Attachment preparation must not overwrite bytes reachable from the existing library.
- Let Workspace connect outgoing editor snapshots to the library. Flush before switching; failed flushes preserve the open editor and entered data for retry.

**Exit:** file widgets never write storage directly. Failed saves or transfers preserve current content and existing attachment bytes. Late saves cannot target a subsequently selected file.

## 4. Introduce editor operations and typed history

- Introduce `EditorSession` as the sole writer of the open document. Move selection IDs, active/editing state, tool choice, defaults, and history out of page state and element models.
- Route document changes through named operations. Keep algorithms in geometry/history and I/O with its owners so the session remains an editor coordinator.
- Replace JSON-based history capture and save-driven change detection with typed snapshots and explicit operation boundaries. Preserve the 50-operation limit.
- Group transforms, content-edit sessions, Auto promotion, and placement transitions according to the interaction model. Keep tool-only history distinct from document changes and saves.
- Reconcile history restoration by element ID and type. Define invalidation tokens before migrating asynchronous clipboard, image, and font workflows; cancel according to each workflow's existing lifetime rules.

**Exit:** views and resources cannot mutate saved fields. No-op behavior, redo invalidation, tool restoration, and grouped operations match the interaction model. Autosave timing does not determine undo boundaries.

## 5. Separate rendering resources and input

- Introduce `CanvasView` as the document-to-grid projection and owner of the grid controller. Retain element resources by ID/type outside lazily culled widgets.
- Split existing models into immutable values, required resource owners, and views. Preserve controllers, scroll positions, loaded images, and measured layout when identity survives restoration.
- Move pointer arbitration into `CanvasInput` and focus-aware keyboard handling into `CanvasShortcuts`. Use explicit gesture transitions and preserve native browser clipboard-event access.
- Separate creation tools from persisted element views. Pen, arrow, shape, and placement tools produce values; session operations commit them.
- In the owned `infinite_lazy_grid`, expose its existing arrangement calculation as a non-mutating query and have mutating commands reuse it. The app commits proposed order through its session and projects it back to the grid.
- Keep generic navigation mechanics in the grid. Improve its public navigation lifecycle if necessary to remove application dependence on callback ordering; keep tool/selection policy in the app.
- Remove old shared-private tool libraries and model wrappers as their callers migrate.

**Exit:** document geometry/order has one authority. Undo and culling preserve surviving resources. Two-finger takeover and cancellation cannot restart interrupted gestures or apply stale edits.

## 6. Consolidate presentation and guidance

- Put element views, editors, options, and resources in their owning element folders. Put shared canvas chrome in editor widgets and file UI in library widgets.
- Consolidate genuinely shared styling and interaction rules using existing app primitives and theme facilities. Give retained shared widgets production consumers; remove unused alternatives and their previews.
- Keep semantic app-wide geometry in theme and component-specific layout local. Preserve accessibility, keyboard behavior, and bounded pointer scrolling.
- Route group Arrange through the existing group operation instead of retaining the throwing placeholder. Additional group transform UI requires its own product design.
- Move tests to the behavior's owner, including code/selection tests currently in the pen suite. Update imports, previews, fixtures, and nested `AGENTS.md` guidance with each move.
- Update the interaction model for the group Arrange correction and any other intentional behavior change. Remove obsolete implementation paths and contradictory guidance.

**Exit:** the tree matches ownership, independent components have ordinary imports, shared UI has actual consumers, and guidance describes the implemented boundaries.

## Verification and completion

Reuse existing tests and move them with their owners. Add focused cases for new contracts and uncovered failure paths; avoid duplicating existing scenarios or asserting theme-token values.

| Area            | Required coverage                                                                                                                                                           |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Document/codecs | Mixed-element round trips, immutable snapshots, malformed geometry, duplicate IDs, unsupported versions, attachment/path/size/archive validation.                           |
| Editor/history  | Tool choice and placement undo, Auto promotion and arrangement, grouping, no-ops, redo invalidation, independent interaction states, focused text undo.                     |
| Resources       | Stable controllers, scrolling, images, and measured geometry across restoration and culling; source changes reload normally.                                                |
| Async work      | Delayed clipboard reads/uploads after undo, removal, disposal, switching, and replacement; stale completion cannot alter restored content; canceled writes attempt cleanup. |
| Durability      | Save failures and retries, overlapping revisions, captured file targets, failed flushes, staged import/restore failures, preservation of existing attachments.              |
| Input/UI        | Zoom/rotation transforms, pointer thresholds and cancellation, two-finger takeover, menu/keyboard priority, native clipboard access, bounded scrolling, accessibility.      |
| Boundaries      | A small import check rejects document-to-presentation, library-to-editor, shared-UI-to-feature, and browser-implementation imports from shared logic.                       |

Run browser-dependent tests with `CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome <test-file>`. Check analysis and `flutter build web` for migrated code. Use focused checks while extracting; run the full Chrome test suite once before committing feature/fix work. The documentation stage needs link, diagram, and diff review only.

The refactor is complete when all writers follow their ownership rules, the old paths are removed, behavioral checks pass, and the architecture and interaction documents agree with the application.
