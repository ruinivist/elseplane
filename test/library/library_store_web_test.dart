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
import 'package:elseplane/library/transfer/canvas_library_archive.dart';
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

  test('persists confirmed and pending GitHub tracking but excludes both from ZIP backup', () async {
    final tracking = GitHubCanvasTracking(
      path: 'Notes.canvas',
      documentSha: 'document-sha',
      attachmentShas: {'Notes/attachments/image.png': 'blob-sha'},
      attachmentNames: {'attachments/00000000-0000-4000-8000-000000000000.png': 'attachments/image.png'},
    );
    final pending = GitHubCanvasTracking(
      path: 'Notes-next.canvas',
      documentSha: 'pending-document-sha',
      attachmentShas: const {},
      attachmentNames: const {},
    );
    final library = CanvasLibrary(
      currentId: 'canvas',
      githubDestination: const GitHubDestination(
        accountId: 1,
        repositoryId: 2,
        owner: 'owner',
        repository: 'repo',
        branch: 'main',
      ),
      files: [
        CanvasFile(
          id: 'canvas',
          name: 'Notes',
          document: CanvasLibrary.emptyDocument,
          githubTracking: tracking,
          githubPendingTracking: pending,
        ),
      ],
    );

    expect(tracking.attachmentShas.clear, throwsUnsupportedError);
    expect(tracking.attachmentNames.clear, throwsUnsupportedError);
    await PreferencesLibraryStore().save(library);

    final restored = (await PreferencesLibraryStore().load())!;
    expect(restored.githubDestination?.toJson(), library.githubDestination!.toJson());
    expect(restored.current.githubTracking?.toJson(), tracking.toJson());
    expect(restored.current.githubPendingTracking?.toJson(), pending.toJson());
    expect(restored.current.githubWriteUnconfirmed, isTrue);

    final portable = await decodeCanvasLibraryArchive(await encodeCanvasLibraryArchive(library, _EmptyAttachments()));
    expect(portable.library.githubDestination, isNull);
    expect(portable.library.current.githubTracking, isNull);
    expect(portable.library.current.githubPendingTracking, isNull);
    expect(portable.library.current.githubWriteUnconfirmed, isFalse);
  });

  test('rejects malformed persisted GitHub metadata', () {
    final initial = CanvasLibrary.initial();
    final library = initial.toJson();
    final file = initial.current.toJson()
      ..['githubTracking'] = {
        'path': 'Canvas.canvas',
        'documentSha': 'sha',
        'attachmentShas': <String, Object?>{'attachments/image.png': 3},
        'attachmentNames': <String, String>{},
      };
    library['files'] = [file];

    expect(() => CanvasLibrary.fromJson(library), throwsFormatException);

    final pendingLibrary = initial.toJson();
    final pendingFile = initial.current.toJson()
      ..['githubPendingTracking'] = {
        'path': 'Canvas.canvas',
        'documentSha': 'sha',
        'attachmentShas': <String, Object?>{},
        'attachmentNames': 3,
      };
    pendingLibrary['files'] = [pendingFile];
    expect(() => CanvasLibrary.fromJson(pendingLibrary), throwsFormatException);
  });

  test('rejects folder GitHub tracking in either state', () {
    final tracking = GitHubCanvasTracking(
      path: 'Notes.canvas',
      documentSha: 'sha',
      attachmentShas: const {},
      attachmentNames: const {},
    );
    for (final key in ['githubTracking', 'githubPendingTracking']) {
      final library = CanvasLibrary.initial().toJson();
      library['files'] = [
        {
          'id': 'folder',
          'name': 'Folder',
          'parentId': null,
          'document': null,
          key: tracking.toJson(),
        },
        (library['files']! as List).single,
      ];
      expect(() => CanvasLibrary.fromJson(library), throwsFormatException);
    }
  });

  test('loads library snapshots written before GitHub metadata existed', () {
    final library = CanvasLibrary.initial().toJson()..remove('githubDestination');
    for (final file in library['files']! as List<dynamic>) {
      (file as Map<String, dynamic>)
        ..remove('githubTracking')
        ..remove('githubPendingTracking')
        ..remove('githubWriteUnconfirmed');
    }

    final restored = CanvasLibrary.fromJson(library);
    expect(restored.githubDestination, isNull);
    expect(restored.current.githubTracking, isNull);
    expect(restored.current.githubWriteUnconfirmed, isFalse);
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
