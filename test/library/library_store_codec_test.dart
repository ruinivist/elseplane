import 'dart:convert';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_store_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canvas edits write only the changed document record', () {
    final previous = _library();
    final updated = previous.replace(CanvasFile(id: 'a', name: 'A', document: _document(CanvasBackgroundKind.plain)));

    final writes = LibraryStoreCodec.calculateWrites(previous, updated);

    expect(writes.metadata, isNull);
    expect(writes.documentPuts, {'a': jsonEncode(updated.file('a').document!.toJson())});
    expect(writes.documentDeletes, isEmpty);
  });

  test('metadata changes and moves do not rewrite unchanged documents', () {
    final previous = _library();
    final renamed = previous.replace(CanvasFile(id: 'a', name: 'Renamed', document: previous.file('a').document));
    final destination = previous.move('a', parentId: 'folder');

    for (final next in [renamed, destination]) {
      final writes = LibraryStoreCodec.calculateWrites(previous, next);
      final metadata = jsonDecode(writes.metadata!) as Map<String, dynamic>;
      expect(metadata.keys, ['version', 'currentId', 'githubDestination', 'githubImportPromptPending', 'entries']);
      expect(
        (metadata['entries'] as List<dynamic>).every((entry) => !(entry as Map).containsKey('document')),
        isTrue,
      );
      expect(writes.documentPuts, isEmpty);
      expect(writes.documentDeletes, isEmpty);
    }
    final movedEntries =
        (jsonDecode(LibraryStoreCodec.calculateWrites(previous, destination).metadata!)
                as Map<String, dynamic>)['entries']
            as List<dynamic>;
    final movedEntry = movedEntries.cast<Map<String, dynamic>>().singleWhere((entry) => entry['id'] == 'a');
    expect(movedEntry['parentId'], 'folder');
  });

  test('create and delete include the metadata and exact document records', () {
    final previous = _library();
    final created = CanvasLibrary(
      currentId: previous.currentId,
      files: [
        ...previous.files,
        CanvasFile(id: 'c', name: 'C', document: _document(CanvasBackgroundKind.plain)),
      ],
    );
    final deleted = CanvasLibrary(
      currentId: previous.currentId,
      files: previous.files.where((file) => file.id != 'b').toList(),
    );

    final createWrites = LibraryStoreCodec.calculateWrites(previous, created);
    expect(createWrites.metadata, isNotNull);
    expect(createWrites.documentPuts.keys, ['c']);
    expect(createWrites.documentDeletes, isEmpty);

    final deleteWrites = LibraryStoreCodec.calculateWrites(previous, deleted);
    expect(deleteWrites.metadata, isNotNull);
    expect(deleteWrites.documentPuts, isEmpty);
    expect(deleteWrites.documentDeletes, ['b']);
  });

  test('replacement writes a changed document for the same canvas id', () {
    final previous = _library();
    final replacement = previous.replace(
      CanvasFile(id: 'a', name: 'A', document: _document(CanvasBackgroundKind.plain)),
    );

    final writes = LibraryStoreCodec.calculateWrites(previous, replacement);

    expect(writes.metadata, isNull);
    expect(writes.documentPuts.keys, ['a']);
    expect(writes.documentDeletes, isEmpty);
  });

  test('equivalent metadata and identical documents produce no writes', () {
    const destination = GitHubDestination(
      accountId: 1,
      repositoryId: 2,
      owner: 'owner',
      repository: 'repo',
      branch: 'main',
    );
    final previous = _library().copyWith(githubDestination: destination);
    final next = CanvasLibrary(
      currentId: previous.currentId,
      githubDestination: const GitHubDestination(
        accountId: 1,
        repositoryId: 2,
        owner: 'owner',
        repository: 'repo',
        branch: 'main',
      ),
      files: [...previous.files],
    );

    expect(LibraryStoreCodec.calculateWrites(previous, next).isEmpty, isTrue);
  });

  test('first save seeds metadata and every canvas document', () {
    final initial = CanvasLibrary.initial();
    final library = CanvasLibrary(
      currentId: initial.currentId,
      files: initial.files,
      githubImportPromptPending: true,
    );

    final writes = LibraryStoreCodec.calculateWrites(null, library);

    expect(writes.metadata, isNotNull);
    expect(writes.documentPuts.keys, [initial.currentId]);
    expect(writes.documentDeletes, isEmpty);
  });

  test('write calculation rejects an invalid next library', () {
    final invalid = CanvasLibrary(
      currentId: '',
      files: [CanvasFile(id: '', name: 'A', document: _document(CanvasBackgroundKind.plain))],
    );

    expect(() => LibraryStoreCodec.calculateWrites(null, invalid), throwsFormatException);
  });

  test('record codec round trips metadata, folders, documents, and GitHub values', () {
    final baseline = GitHubBaseline.capture(
      const GitHubDestination(accountId: 1, repositoryId: 2, owner: 'owner', repository: 'repo', branch: 'main'),
      'A.canvas.json',
      _document(CanvasBackgroundKind.dotGrid),
      {},
    );
    final library = CanvasLibrary(
      currentId: 'a',
      githubDestination: const GitHubDestination(
        accountId: 1,
        repositoryId: 2,
        owner: 'owner',
        repository: 'repo',
        branch: 'main',
      ),
      githubImportPromptPending: true,
      files: [
        CanvasFile(id: 'a', name: 'A', document: _document(CanvasBackgroundKind.dotGrid), githubBaseline: baseline),
        const CanvasFile(id: 'folder', name: 'Folder'),
      ],
    );
    final writes = LibraryStoreCodec.calculateWrites(null, library);

    final restored = LibraryStoreCodec.decodeRecords(writes.metadata!, writes.documentPuts);

    expect(restored.currentId, 'a');
    expect(restored.githubDestination?.owner, 'owner');
    expect(restored.githubImportPromptPending, isTrue);
    expect(restored.files.map((file) => file.isFolder), [false, true]);
    expect(restored.current.document!.toJson(), library.current.document!.toJson());
    expect(restored.current.githubBaseline!.toJson(), baseline.toJson());
  });

  test('record codec rejects invalid structure, missing documents, and extra documents', () {
    final library = _library();
    final writes = LibraryStoreCodec.calculateWrites(null, library);
    final documents = {...writes.documentPuts}..remove('b');

    expect(() => LibraryStoreCodec.decodeRecords(writes.metadata!, documents), throwsFormatException);
    expect(
      () => LibraryStoreCodec.decodeRecords(writes.metadata!, {...writes.documentPuts, 'extra': '{}'}),
      throwsFormatException,
    );
    expect(
      () => LibraryStoreCodec.decodeRecords('{"version":2}', writes.documentPuts),
      throwsFormatException,
    );

    final cyclicMetadata = jsonDecode(writes.metadata!) as Map<String, dynamic>;
    final entries = cyclicMetadata['entries'] as List<dynamic>;
    (entries.last as Map<String, dynamic>)['parentId'] = 'folder';
    expect(
      () => LibraryStoreCodec.decodeRecords(jsonEncode(cyclicMetadata), writes.documentPuts),
      throwsFormatException,
    );
  });
}

CanvasLibrary _library() => CanvasLibrary(
  currentId: 'a',
  files: [
    CanvasFile(id: 'a', name: 'A', document: _document(CanvasBackgroundKind.dotGrid)),
    CanvasFile(id: 'b', name: 'B', document: _document(CanvasBackgroundKind.plain)),
    const CanvasFile(id: 'folder', name: 'Folder'),
  ],
);

CanvasDocument _document(CanvasBackgroundKind background) => CanvasDocument(background: background, elements: []);
