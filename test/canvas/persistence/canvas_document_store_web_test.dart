// Verifies browser persistence for the current canvas document.
// Exercises the document store with web shared preferences.

@TestOn('browser')
library;

import 'dart:convert';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/persistence/canvas_document_store.dart';
import 'package:elseplane/canvas/persistence/canvas_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

// ---------- Tests ----------

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    await SharedPreferencesAsync().remove(CanvasDocumentStore.libraryKey);
  });

  test('starts an empty library when browser storage has no saved library', () async {
    final store = CanvasDocumentStore();

    expect(await store.load(), isNull);
    expect(store.library.files, hasLength(1));
    expect(store.library.current.document!.toJson(), CanvasLibrary.emptyDocument.toJson());
  });

  test('persists the current canvas document in browser storage', () async {
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [],
    );
    final store = CanvasDocumentStore();

    await store.save(document);

    expect((await store.load())?.toJson(), document.toJson());
  });

  test('retains existing canvas and restores folders and the selected file', () async {
    final original = CanvasDocument(background: CanvasBackgroundKind.plain, elements: []);
    await SharedPreferencesAsync().setString(
      CanvasDocumentStore.libraryKey,
      jsonEncode(CanvasLibrary.initial(original).toJson()),
    );
    final store = CanvasDocumentStore();
    await store.load();
    final originalId = store.library.currentId;
    final next = CanvasLibrary(
      currentId: 'second',
      files: [
        store.library.current,
        const CanvasFile(id: 'folder', name: 'Notes'),
        CanvasFile(id: 'second', name: 'Ideas', parentId: 'folder', document: CanvasLibrary.emptyDocument),
      ],
    );
    await store.saveLibrary(next);
    final restored = CanvasDocumentStore();
    expect((await restored.load())!.background, CanvasBackgroundKind.dotGrid);
    expect(restored.library.path('second').map((file) => file.name), ['Notes', 'Ideas']);
    expect(restored.library.file(originalId).document!.toJson(), original.toJson());
    expect(restored.library.currentId, 'second');
    expect(
      () => CanvasLibrary.fromJson({
        ...next.toJson(),
        'files': [const CanvasFile(id: 'folder', name: 'Cycle', parentId: 'folder').toJson()],
      }),
      throwsFormatException,
    );
  });

  test('persists sibling order and folder moves without changing canvas contents', () async {
    final library = CanvasLibrary(
      currentId: 'a',
      files: [
        CanvasFile(id: 'a', name: 'A', document: CanvasLibrary.emptyDocument),
        CanvasFile(id: 'b', name: 'B', document: CanvasLibrary.emptyDocument),
        const CanvasFile(id: 'folder', name: 'Folder'),
        const CanvasFile(id: 'nested', name: 'Nested', parentId: 'folder'),
        CanvasFile(id: 'child', name: 'Child', parentId: 'nested', document: CanvasLibrary.emptyDocument),
        CanvasFile(id: 'duplicate', name: 'A', parentId: 'folder', document: CanvasLibrary.emptyDocument),
      ],
    );

    final reordered = library.move('b', parentId: null, beforeId: 'a');
    expect(reordered.files.where((file) => file.parentId == null).map((file) => file.id), ['b', 'a', 'folder']);
    final nested = reordered.move('b', parentId: 'nested');
    expect(nested.file('b').parentId, 'nested');
    final outdented = nested.move('b', parentId: null);
    expect(outdented.files.where((file) => file.parentId == null).map((file) => file.id), ['a', 'folder', 'b']);
    expect(outdented.currentId, 'a');
    expect(outdented.file('child').parentId, 'nested');
    final movedFolder = outdented.move('nested', parentId: null);
    expect(movedFolder.path('child').map((file) => file.id), ['nested', 'child']);
    expect(() => outdented.move('folder', parentId: 'nested'), throwsFormatException);
    expect(() => outdented.move('a', parentId: 'folder'), throwsFormatException);
    expect(identical(outdented.move('b', parentId: null), outdented), isTrue);

    final store = CanvasDocumentStore();
    await store.saveLibrary(outdented);
    final restored = CanvasDocumentStore();
    await restored.load();
    expect(restored.library.files.map((file) => file.id), outdented.files.map((file) => file.id));
    expect(restored.library.file('b').parentId, isNull);
    expect(restored.library.current.document!.toJson(), library.current.document!.toJson());
  });
}
