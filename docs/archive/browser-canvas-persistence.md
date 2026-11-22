# Move browser canvas saves to IndexedDB

Status: complete

## Scope

Implement [ADR 0007](../adr/0007-store-canvases-individually-in-indexeddb.md) and the [browser canvas persistence specification](../specs/browser-canvas-persistence.md). Replace the whole-library save boundary once, for every caller. Do not add a pen-only path, a new dependency, lazy document loading, or changes to the editor, attachment store, or transfer formats. This is a clean development cutover: no migration, fallback, dual writes, cleanup of old browser keys, or compatibility tests.

## Design decided by lead

### Ownership and write contract

- `LibraryController` remains the sole owner of the published `CanvasLibrary`, pending revisions, and persistence queue. Keep `load() -> Future<CanvasLibrary?>`. Replace `LibraryStore.save(snapshot)` with `Future<void> save(CanvasLibrary next, {required CanvasLibrary? previous})`. `previous` is the last successfully loaded or published snapshot, never the snapshot with pending edits overlaid. Pass `null` only for the first write when load found no saved library. Track that case with a flag; do not keep a second copy of the library in the controller or store.
- Route every write through the controller's existing `_persist` boundary. Advance the published snapshot and durable revisions only after the store commits. Keep the debounce, queue, and revision rules, including import replacement tokens and retry behavior. Preserve attachment copying and import write order; the IndexedDB transaction starts at the existing library publication step.
- Put the shared record codec and write calculation in `lib/library/library_store_codec.dart`, with no browser imports. Derive one write set from `previous` and `next`: optional metadata replacement, canvas document puts by ID, and document deletes by ID. A null `previous` seeds the full library, including the initial canvas if the first action changed only metadata. For later writes, compare documents by identity: library operations retain unchanged immutable document instances. Compare metadata independently of document contents, using ordered entry fields and the immutable GitHub metadata values. Do not call `CanvasLibrary.toJson()` or serialize documents to detect changes. A no-op opens no write transaction.

### Record layout and transactions

- Use the existing `package:web` bindings in `lib/library/library_store_web.dart`. Database `elseplane.canvas.library`, schema version `1`: `metadata` holds one JSON string under `library`, and `documents` holds a direct versioned `CanvasDocument` JSON string per canvas ID. The metadata JSON has its own version (`1`), current canvas ID, GitHub destination and import-prompt state, and ordered entries with ID, name, parent ID, explicit canvas/folder kind, and any GitHub baseline. It contains no document data. Folders have no document records.
- Read metadata and document keys and values in one read transaction before decoding. Require a valid library and an exact match between canvas IDs in metadata and document keys. Missing metadata with existing documents, missing or extra records, and malformed records are load errors, not empty libraries. Reuse the existing document and GitHub codecs and preserve the library structure checks from the old decoder. Remove the old whole-library JSON codec once its callers are gone.
- Encode the write set before opening the write transaction. For a document-only write, use only `documents` and put only changed records. For a metadata-only write, use only `metadata`. Include both stores in one transaction when both change. Resolve success on transaction completion, not individual request success; abort on a failed request or precondition. Keep requests inside the active transaction and keep preference reads and other unrelated async work outside it.
- Protect record consistency if tabs overlap without adding cross-tab edit sync: initialization checks for absent metadata in its write transaction; later metadata writes check that the stored metadata still matches the encoded prior metadata before changing records; document-only puts require their target keys to still exist. A stale structural write fails rather than creating orphans or reviving deleted records. Do not merge concurrent edits to the same live canvas.

### Cutover

- `IndexedDbLibraryStore.load` reads only IndexedDB. `ElseplaneApp` switches its default store once and keeps existing store injection for tests. Give the store an optional database name for isolated browser tests, defaulting to the production name. Remove `PreferencesLibraryStore` and replace its fixtures. Keep platform code out of the store contract, controller, and model. Do not change preference use for settings or touch OPFS data.

## Worker split

Dispatch A and B to separate workers in parallel using the interface and schema above. They own disjoint files, and neither should add a temporary compatibility layer to compile alone. Once both are in the integration tree, the B worker handles the single app cutover in C. The lead owns integration and the release decision.

| Slice | Owned files and deliverable | Required checks |
| --- | --- | --- |
| A. Record codec and IndexedDB | `lib/library/{library_store_codec,library_store_web,canvas_library}.dart` and `test/library/library_store{_codec,_web}_test.dart`. Implement the record layout, validation, and transactions. | Assert exact write sets for an edit, metadata change, move, create, delete, replace, no-op, and first save. Chrome coverage for reopen, invalid records, and abort rollback. To catch a sibling rewrite, change B in IndexedDB after loading A and B, save an edit to A, and verify B's newer stored value survives. |
| B. Store contract and queue | `lib/library/{library_store,library_controller}.dart`, `test/library/library_controller*_test.dart`, `test/library/widgets/`, `test/canvas/test_helpers.dart`, and store doubles in `test/app/`. Update the queue boundary and all save overrides. | Controller tests prove correct previous/next snapshots on first save, retry, edits during an in-flight save, import overwrite, and GitHub baseline updates. Existing failure and handoff tests still pass. |
| C. App cutover and test fixtures | `lib/app/app.dart`, boot/reopen cases in `test/app/workspace_loading_test.dart`, and remaining preference-backed library fixtures under `test/canvas/`. Keep actual storage tests on IndexedDB with isolated database names; use injected stores for tests unrelated to persistence. | Boot, save, reopen, and verify restored state and existing load-failure feedback. Check that no production caller or fixture still uses the removed library store. |

**Worker discretion:** Local helper names, test fixtures, and browser request plumbing within the design. Report files changed, checks run, and any gaps. **Escalate:** Any change to the store interface, schema, ownership, dependencies, or transfer behavior. Run cross-slice checks after integration.

## Integration and release checks

- [x] Run the focused storage and workspace reopen tests, `flutter analyze`, and `flutter build web`. The full Chrome suite covers library, workspace handoff, transfer, and GitHub workspace tests: 785 passed, 4 skipped.
- [x] In a real browser, draw distinct strokes on two canvases, switch canvases, and reload. Both strokes and the last-opened selection restored. The automated storage tests cover nested libraries and verify that a canvas-only save leaves metadata and sibling documents untouched. Manual image reload and performance measurements were not completed.
- [x] Review the combined diff with both independent reviewers. Neither reported a defect.
- [x] Update the persistence contract and documentation map, and archive this plan.
