// Verifies atomic library snapshot persistence without controller-owned state.
// Exercises the preferences adapter in the browser.

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/library/transfer/canvas_transfer_zip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

// ---------- Tests ----------

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    await SharedPreferencesAsync().remove(PreferencesLibraryStore.libraryKey);
  });

  test('starts an empty library when browser storage has no saved library', () async {
    final store = PreferencesLibraryStore();

    expect(await store.load(), isNull);
  });

  test('persists the current canvas document in browser storage', () async {
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [],
    );
    final store = PreferencesLibraryStore();

    await store.save(CanvasLibrary.initial(document));

    expect((await store.load())?.current.document?.toJson(), document.toJson());
  });

  test('retains existing canvas and restores folders and the selected file', () async {
    final original = CanvasDocument(background: CanvasBackgroundKind.plain, elements: []);
    await SharedPreferencesAsync().setString(
      PreferencesLibraryStore.libraryKey,
      jsonEncode(CanvasLibrary.initial(original).toJson()),
    );
    final store = PreferencesLibraryStore();
    final loaded = (await store.load())!;
    final originalId = loaded.currentId;
    final next = CanvasLibrary(
      currentId: 'second',
      files: [
        loaded.current,
        const CanvasFile(id: 'folder', name: 'Notes'),
        CanvasFile(id: 'second', name: 'Ideas', parentId: 'folder', document: CanvasLibrary.emptyDocument),
      ],
    );
    await store.save(next);
    final restored = PreferencesLibraryStore();
    final restoredLibrary = (await restored.load())!;
    expect(restoredLibrary.current.document!.background, CanvasBackgroundKind.dotGrid);
    expect(restoredLibrary.path('second').map((file) => file.name), ['Notes', 'Ideas']);
    expect(restoredLibrary.file(originalId).document!.toJson(), original.toJson());
    expect(restoredLibrary.currentId, 'second');
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

    final store = PreferencesLibraryStore();
    await store.save(outdented);
    final restored = PreferencesLibraryStore();
    final restoredLibrary = (await restored.load())!;
    expect(restoredLibrary.files.map((file) => file.id), outdented.files.map((file) => file.id));
    expect(restoredLibrary.file('b').parentId, isNull);
    expect(restoredLibrary.current.document!.toJson(), library.current.document!.toJson());
  });

  test('persists the GitHub destination without per-canvas tracking', () async {
    final library = CanvasLibrary(
      currentId: 'canvas',
      githubDestination: const GitHubDestination(
        accountId: 1,
        repositoryId: 2,
        owner: 'owner',
        repository: 'repo',
        branch: 'main',
      ),
      files: [CanvasFile(id: 'canvas', name: 'Notes', document: CanvasLibrary.emptyDocument)],
    );

    await PreferencesLibraryStore().save(library);

    final restored = (await PreferencesLibraryStore().load())!;
    expect(restored.githubDestination?.toJson(), library.githubDestination!.toJson());
    expect(restored.current.document?.toJson(), library.current.document?.toJson());
    expect(restored.current.toJson().keys, isNot(contains('githubTracking')));
    expect(restored.current.toJson().keys, isNot(contains('githubPendingTracking')));

    final portable = await encodeTransfer(library, _EmptyAttachments(), TransferScope.wholeLibrary);
    final decoded = await decodeTransfer(ZipTransferSource(encodeTransferZip(portable)));
    expect(decoded.canvases.keys, {'Notes.canvas.json'});
    expect(decoded.canvases['Notes.canvas.json']?.toJson(), library.current.document?.toJson());
  });

  test('ignores malformed obsolete per-canvas tracking fields without losing library data', () {
    final initial = CanvasLibrary.initial();
    final library = initial.toJson()
      ..['githubDestination'] = const GitHubDestination(
        accountId: 1,
        repositoryId: 2,
        owner: 'owner',
        repository: 'repo',
        branch: 'main',
      ).toJson();
    final file = initial.current.toJson()
      ..['githubTracking'] = <String, Object?>{'bad': 3}
      ..['githubPendingTracking'] = 'obsolete malformed data';
    library['files'] = [file];

    final restored = CanvasLibrary.fromJson(library);
    expect(restored.files, hasLength(1));
    expect(restored.current.document?.toJson(), initial.current.document?.toJson());
    expect(restored.githubDestination?.owner, 'owner');
  });

  test('loads library snapshots written before GitHub metadata existed', () {
    final library = CanvasLibrary.initial().toJson()..remove('githubDestination');
    final restored = CanvasLibrary.fromJson(library);
    expect(restored.githubDestination, isNull);
  });
}

class _EmptyAttachments implements AttachmentStore {
  @override
  Future<void> delete(String path) async => throw UnimplementedError();

  @override
  Future<Uint8List> read(String path) async => throw UnimplementedError();

  @override
  Future<Uint8List?> readIfExists(String path) async => null;

  @override
  Future<void> write(String path, Uint8List bytes) async => throw UnimplementedError();
}
