# Refactor roadmap

Implement the [target architecture](ARCHITECTURE.md) in the order below. Each stage must leave a runnable web app and remove the superseded implementation. This roadmap is migration work; the architecture document holds the lasting rules.

## Baseline and constraints

The source review found ownership problems across four areas:

- `canvas_page.dart` combines input, history, selection, rendering integration, clipboard, file operations, and saving.
- Document definitions import background rendering, syntax highlighting, and font-loading definitions.
- Mutable element models combine saved content, interaction state, Flutter resources, and asynchronous work.
- Tool libraries use shared-private `part` files, and production controls repeat styles despite preview-only shared buttons.

Preserve the [interaction model](Interaction%20model.md) and its [paste cancellation decision](adr/0001-cancel-unfinished-pastes.md), including tool history, per-object Auto arrangement, independent activation/selection/editing, touch navigation, and focused editors' local undo. Retain existing element types, library hierarchy, clipboard workflows, and project/backup formats during structural migration unless an explicit format change is necessary. Backward compatibility with historical versions is not required; unreadable data must still fail visibly without being overwritten.

Keep current dependencies and browser storage initially. Shared code must isolate browser APIs; native storage implementation and non-web verification are separate work. Self-hosting, collaboration, extensions, LSP, and additional media types do not belong to this refactor.

## 1. Establish the architectural contract

**Status:** complete.

- Publish the [architectural constitution](ARCHITECTURE.md) and link it and this roadmap from root `AGENTS.md`.
- Clearly distinguish target ownership from the current implementation.
- Treat the interaction model as the behavioral authority; older notes do not override it.

**Exit:** contributors can locate the owner of a new responsibility and identify its allowed dependencies. No application behavior changes in this documentation stage.

## 2. Establish document and geometry boundaries

**Status:** complete.

- Introduce immutable document and element values with immutable collections. Keep sealed element variants together and retain strict serialization validation.
- Move saved background/language enums into the document. Move their rendering/highlighting mappings to presentation. Separate saved font names from font catalog loading.
- Use native graphics values consistently in memory. Keep wire-format and hex-input conversion at their boundaries.
- Extract reusable path, bounds, hit-test, and transform calculations into `canvas/geometry/`. Keep UI measurements and creation defaults with their actual owners.
- Update current models, tools, transfer codecs, clipboard handling, generated serializers, demo data, fixtures, and tests together. Existing model setters can replace immutable values while their mutation ownership migrates in stage 4.

**Exit:** the document imports no presentation or concrete storage. Round trips and invalid-input behavior remain correct. No caller can mutate a published document or its nested collections.

Document values, enums, and private codec helpers now share one immutable document library. Geometry uses ordinary imports under `canvas/geometry/`. Saved font names no longer depend on catalog membership; unavailable fonts retain their saved names and render with the bundled fallback. The source import check runs with `flutter test test/architecture/document_boundaries_test.dart`.

## 3. Separate library durability from widgets

**Status:** complete.

- Move library rules and file UI into `library/`; move attachment contracts and browser storage into `attachments/`.
- Establish `LibraryController` as the library owner and single persistence-queue owner. Make `LibraryStore` an injectable snapshot read/write contract, without a mutable public library.
- Capture file identity, revision, and immutable content for every save. Keep failures visible and preserve dirty state until its corresponding revision is durable.
- Move create, rename, move, delete, import, export, backup, and restore orchestration out of canvas/file-picker widgets. Widgets own inline drafts, navigation, focus, and confirmations.
- Use the [staged import protocol](ARCHITECTURE.md#operations-and-correctness). Preserve path, byte-size, archive-entry, image, and attachment-reference validation. Attachment preparation must not overwrite bytes reachable from the existing library.
- Let Workspace connect outgoing editor snapshots to the library. Cancel unfinished pastes and uploads, then flush completed edits before switching; failed flushes preserve the open editor and completed data for retry. Navigation never waits for canceled work.

**Exit:** file widgets never write storage directly. Failed saves or transfers preserve current content and existing attachment bytes. Late saves cannot target a subsequently selected file.

Workspace now connects canvas snapshots to `LibraryController`; the controller owns pending revisions, file operations, and the persistence queue. Snapshot storage retains the existing preferences key and format. Canvas import, library restore, and Demo creation stage fresh attachments before the metadata commit, with cleanup limited to unpublished paths. File UI and transfer tests follow their library or app owner; attachment tests live with attachments. The VM source checks cover document, library, shared UI, and browser implementation boundaries.

## 4. Introduce editor operations and typed history

**Status:** complete.

- Introduce `EditorSession` as the sole writer of the open document. Move selection IDs, active/editing state, tool choice, defaults, and history out of page state and element models.
- Route document changes through named operations. Keep algorithms in geometry/history and I/O with its owners so the session remains an editor coordinator.
- Replace JSON-based history capture and save-driven change detection with typed snapshots and explicit operation boundaries. Preserve the 50-operation limit.
- Group transforms, content-edit sessions, Auto promotion, and placement transitions according to the interaction model. Keep tool-only history distinct from document changes and saves.
- Reconcile history restoration by element ID and type. Define invalidation tokens before migrating asynchronous clipboard, image, and font workflows; cancel according to the paste cancellation decision and each other workflow's lifetime rules.

**Exit:** views and resources cannot mutate saved fields. No-op behavior, redo invalidation, tool restoration, and grouped operations match the interaction model. Autosave timing does not determine undo boundaries.

Workspace owns `EditorSession`, which publishes immutable documents through named operations. Typed history retains document values and explicit operation groups without JSON comparisons. Selection, activation, logical editing contexts, tools, and drawing defaults belong to the session; existing models retain presentation resources and request session edits. Session tokens cancel stale clipboard and upload completions. The grid's read-only `arrangedOrder` query and value-only creation callbacks were brought forward so all saved changes can pass through the session. Rendering and pointer extraction remain in stage 5.

## 5. Separate rendering resources and input

**Status:** complete. Code blocks keep wrapping fixed off and scroll long lines horizontally, avoiding the re_editor 0.10.0 wrapped-code restoration defect.

- Introduce `CanvasView` as the document-to-grid projection and owner of the grid controller. Retain element resources by ID/type outside lazily culled widgets.
- Split existing models into immutable values, required resource owners, and views. Preserve controllers, scroll positions, loaded images, and measured layout when identity survives restoration.
- Move pointer arbitration into `CanvasInput` and focus-aware keyboard handling into `CanvasShortcuts`. Use explicit gesture transitions and preserve native browser clipboard-event access.
- Finish separating creation tools from persisted element views. Creation callbacks already produce values and session operations commit them; move their remaining presentation and pointer responsibilities to the intended owners.
- Preserve the read-only arrangement query introduced in stage 4. Keep measured overlap calculations in the grid and saved order in the session as CanvasView takes over projection.
- Keep generic navigation mechanics in the grid. Improve its public navigation lifecycle if necessary to remove application dependence on callback ordering; keep tool/selection policy in the app.
- Remove old shared-private tool libraries and model wrappers as their callers migrate.

**Exit:** document geometry/order has one authority. Undo and culling preserve surviving resources. Two-finger takeover and cancellation cannot restart interrupted gestures or apply stale edits.

CanvasView now owns document projection, the grid controller, and resources retained by element ID/type. Text, code, media, and pen retain only their required resources; shape and arrow views read immutable values directly. CanvasInput owns pointer arbitration and explicit gesture transitions, CanvasShortcuts handles focus-aware commands, and CanvasClipboard owns canvas clipboard edits. Element clipboard and device-image workflows live with their editors. Controllers and loaded images survive culling, removal invalidates image loads before deferred disposal, and session replacement preserves the viewport while starting fresh resource and input lifetimes. Code blocks hardcode wrapping off with a reminder that enabling it reintroduces the re_editor 0.10.0 scroll-restoration defect. The unsupported wrapped-code regression was removed; ordinary resource culling coverage remains. Creation tools and element presentation use ordinary imports under the editor; the old tool parts and model wrappers are removed. The grid now exposes the read-only `overlappingChildren` query for measured, rotated layout rectangles. CanvasView converts marquee bounds into canvas coordinates and delegates overlap calculations to the grid; selection policy remains in CanvasInput. CanvasClipboard serializes captured targets in document stacking order for both Copy and Cut.

Text resources now retain source-keyed inline attachment and HTTPS image loads and decoded streams, loading only when first displayed. Unchanged sources survive culling, editor transitions, and restoration; source removal and element detachment retire their loads immediately. Pen drag completion and non-editing tap promotion now close their own history operations after accepted callbacks. Pan rejection without an actual drag cannot close a tap's operation, and stale completion bindings cannot split a newer gesture. Group batching, font deletion, and transform-layout fixtures use the current pointer/session lifecycles. The re_editor dependency is unchanged.

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
| Async work      | Delayed clipboard reads/uploads after field changes, editing exit, dialogs, undo, removal, disposal, switching, and replacement; stale completion cannot alter restored content; canceled writes attempt cleanup. |
| Durability      | Save failures and retries, overlapping revisions, captured file targets, failed flushes, staged import/restore failures, preservation of existing attachments.              |
| Input/UI        | Zoom/rotation transforms, pointer thresholds and cancellation, two-finger takeover, menu/keyboard priority, native clipboard access, bounded scrolling, accessibility.      |
| Boundaries      | A small import check rejects document-to-presentation, library-to-editor, shared-UI-to-feature, and browser-implementation imports from shared logic.                       |

Run browser-dependent tests with `CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome <test-file>`. Check analysis and `flutter build web` for migrated code. Use focused checks while extracting; run the full Chrome test suite once before committing feature/fix work. The documentation stage needs link, diagram, and diff review only.

The refactor is complete when all writers follow their ownership rules, the old paths are removed, behavioral checks pass, and the architecture and interaction documents agree with the application.
