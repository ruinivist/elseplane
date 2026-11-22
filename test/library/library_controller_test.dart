// Checks revision-aware saves, queued file operations, and transfer replacement.
// Exercises the library controller independently of editor widgets and browser storage.

import 'dart:async';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  late _Store store;
  late _Attachments attachments;
  late LibraryController controller;

  setUp(() async {
    store = _Store();
    attachments = _Attachments();
    controller = LibraryController(store: store, attachments: attachments, files: _Files());
    await controller.load();
  });
  tearDown(() => controller.dispose());

  test('published library copies its collection and never exposes a mutable list', () {
    final files = controller.library.files.toList();
    final snapshot = CanvasLibrary(files: files, currentId: files.first.id);
    files.clear();
    expect(snapshot.files, hasLength(1));
    expect(snapshot.files.clear, throwsUnsupportedError);
    expect(store.writes, isEmpty);
  });

  test('an older successful write cannot acknowledge a newer pending revision', () async {
    final id = controller.library.currentId;
    final first = _document(CanvasBackgroundKind.plain);
    final second = _document(CanvasBackgroundKind.dotGrid);
    final gate = Completer<void>();
    store.gate = gate;
    controller.updateDocument(id, first);
    final saving = controller.flush();
    await store.started.future;
    controller.updateDocument(id, second);
    expect(store.writes.single.next.current.document, same(first));
    expect(store.writes.single.previous, isNull);
    expect(controller.isDirty, isTrue);
    expect(controller.snapshot.current.document, same(second));
    gate.complete();
    await saving;
    expect(store.writes.map((write) => write.next.current.document), [first, second]);
    expect(store.writes.last.previous, same(store.writes.first.next));
    expect(controller.library.current.document, same(second));
    expect(controller.isDirty, isFalse);
  });

  test('failed autosave remains dirty and an explicit retry clears its error', () async {
    store.fail = true;
    final document = _document(CanvasBackgroundKind.plain);
    final failed = Completer<void>();
    controller.addListener(() {
      if (controller.saveError != null && !failed.isCompleted) failed.complete();
    });
    controller.updateDocument(controller.library.currentId, document);
    await failed.future;
    expect(controller.isDirty, isTrue);
    expect(controller.saveError, isNotNull);
    expect(controller.snapshot.current.document, same(document));
    store.fail = false;
    await controller.flush();
    expect(store.writes.map((write) => write.previous), [null, null]);
    expect(controller.library.current.document, same(document));
    expect(controller.isDirty, isFalse);
    expect(controller.saveError, isNull);
  });

  test('queued file operations merge current metadata and retain captured file targets', () async {
    final originalId = controller.library.currentId;
    final other = CanvasFile(id: 'other', name: 'Other', document: CanvasLibrary.emptyDocument);
    await controller.create(other, openId: originalId);
    final gate = Completer<void>();
    store.gate = gate;
    final first = _document(CanvasBackgroundKind.plain);
    controller.updateDocument(originalId, first);
    final saving = controller.flush();
    await store.started.future;
    final renaming = controller.rename(originalId, 'Renamed');
    final selecting = controller.select(other.id);
    gate.complete();
    await Future.wait([saving, renaming, selecting]);
    final lateDocument = _document(CanvasBackgroundKind.dotGrid);
    controller.updateDocument(originalId, lateDocument);
    await controller.flush();
    expect(controller.library.currentId, other.id);
    expect(controller.library.file(originalId).name, 'Renamed');
    expect(controller.library.file(originalId).document, same(lateDocument));
    expect(controller.library.current.document, same(other.document));
  });

  test('ordinary file operations and edits preserve the GitHub destination', () async {
    final id = controller.library.currentId;
    await controller.setGitHubDestination(_destination());
    await controller.create(
      const CanvasFile(id: 'folder', name: 'Folder'),
      openId: id,
    );
    await controller.create(
      CanvasFile(id: 'other', name: 'Other', parentId: 'folder', document: CanvasLibrary.emptyDocument),
    );
    await controller.rename(id, 'Renamed');
    await controller.move(id, parentId: 'folder');
    controller.updateDocument(id, _document(CanvasBackgroundKind.plain));
    await controller.flush();
    await controller.select('other');

    expect(controller.library.githubDestination?.toJson(), _destination().toJson());
    expect(controller.library.file(id).document, isNotNull);
  });

  test('the first metadata save sends a full library with no previous snapshot', () async {
    final initial = controller.library;

    await controller.setGitHubDestination(_destination());

    expect(store.writes, hasLength(1));
    expect(store.writes.single.previous, isNull);
    expect(store.writes.single.next.current.document, same(initial.current.document));
    expect(store.writes.single.next.githubDestination?.toJson(), _destination().toJson());
  });

  test('the first write after load uses the loaded library as previous', () async {
    controller.dispose();
    final saved = CanvasLibrary.initial();
    store = _Store(saved);
    controller = LibraryController(store: store, attachments: attachments, files: _Files());
    await controller.load();

    await controller.rename(saved.currentId, 'Loaded');

    expect(store.writes.single.previous, same(saved));
    expect(store.writes.single.next.current.name, 'Loaded');
  });

  test('GitHub baseline saves compare against the published library', () async {
    final id = controller.library.currentId;
    await controller.setGitHubDestination(_destination());
    final previous = controller.library;
    final baseline = GitHubBaseline.capture(
      _destination(),
      '${previous.current.name}.canvas.json',
      previous.current.document!,
      const {},
    );

    await controller.saveGitHubBaseline(id, baseline);

    expect(store.writes.last.previous, same(previous));
    expect(store.writes.last.next.file(id).githubBaseline, same(baseline));
    expect(store.writes.last.next.file(id).document, same(previous.file(id).document));
  });

  test('library names compare case-sensitively and reject exact duplicates', () async {
    await controller.create(const CanvasFile(id: 'school', name: 'School'));
    await controller.create(const CanvasFile(id: 'lower-school', name: 'school'));
    await expectLater(
      controller.create(const CanvasFile(id: 'duplicate-school', name: 'School')),
      throwsFormatException,
    );
    await controller.create(CanvasFile(id: 'map', name: 'Map', document: CanvasLibrary.emptyDocument));
    await controller.create(CanvasFile(id: 'lower-map', name: 'map', document: CanvasLibrary.emptyDocument));
    await expectLater(
      controller.create(CanvasFile(id: 'duplicate-map', name: 'Map', document: CanvasLibrary.emptyDocument)),
      throwsFormatException,
    );

    await controller.rename('lower-map', 'MAP');
    await expectLater(controller.rename('lower-map', 'Map'), throwsFormatException);

    await controller.create(const CanvasFile(id: 'source', name: 'Source'));
    await controller.create(
      CanvasFile(id: 'nested-guide', name: 'Guide', parentId: 'source', document: CanvasLibrary.emptyDocument),
    );
    await controller.create(CanvasFile(id: 'root-guide', name: 'guide', document: CanvasLibrary.emptyDocument));
    await controller.move('nested-guide', parentId: null);
    expect(controller.library.file('nested-guide').parentId, isNull);

    await controller.create(const CanvasFile(id: 'destination', name: 'Destination'));
    await controller.create(
      CanvasFile(id: 'nested-map', name: 'Map', parentId: 'destination', document: CanvasLibrary.emptyDocument),
    );
    await expectLater(controller.move('nested-map', parentId: null), throwsFormatException);
  });

  test('folder names reserve transfer namespaces and canvas suffix paths', () async {
    await expectLater(
      controller.create(const CanvasFile(id: 'reserved', name: 'attachments')),
      throwsFormatException,
    );
    await controller.create(const CanvasFile(id: 'folder', name: 'Projects'));
    await expectLater(controller.rename('folder', '.git'), throwsFormatException);
    expect(controller.library.file('folder').name, 'Projects');

    await controller.create(CanvasFile(id: 'map', name: 'Map', document: CanvasLibrary.emptyDocument));
    await expectLater(
      controller.create(const CanvasFile(id: 'collision', name: 'Map.canvas.json')),
      throwsFormatException,
    );
    await controller.create(
      CanvasFile(id: 'same-title', name: 'attachments', document: CanvasLibrary.emptyDocument),
    );
    expect(controller.library.serializedPath('same-title'), 'attachments.canvas.json');
  });

  test('last-canvas replacement checks Untitled with exact spelling', () async {
    await controller.create(const CanvasFile(id: 'lower-folder', name: 'untitled'));

    await controller.delete(controller.library.currentId);

    expect(controller.library.files.where((file) => file.name == 'Untitled' && !file.isFolder), hasLength(1));
    expect(controller.library.files.where((file) => file.name == 'untitled' && file.isFolder), hasLength(1));
  });

  test('changing GitHub destination preserves local documents', () async {
    final id = controller.library.currentId;
    final document = controller.library.current.document;
    await controller.setGitHubDestination(_destination());
    await controller.setGitHubDestination(
      const GitHubDestination(accountId: 1, repositoryId: 2, owner: 'renamed', repository: 'repo', branch: 'main'),
    );
    await controller.setGitHubDestination(
      const GitHubDestination(accountId: 1, repositoryId: 2, owner: 'renamed', repository: 'repo', branch: 'next'),
    );

    expect(controller.library.files.map((file) => file.id), [id]);
    expect(controller.library.file(id).document, same(document));
  });

  test('the editor lifetime changes only after a successful overwrite or switch', () async {
    final originalToken = controller.documentToken;
    final id = controller.library.currentId;
    controller.updateDocument(id, _document(CanvasBackgroundKind.plain));
    await controller.flush();
    await controller.rename(id, 'Renamed');
    expect(controller.documentToken, same(originalToken));

    final candidate = TransferImport(
      canvases: {'Renamed.canvas.json': _document(CanvasBackgroundKind.dotGrid)},
      attachments: const {},
      directories: const {},
      skippedCanvases: const [],
    );
    var merge = await controller.previewTransferImport(candidate);
    store.fail = true;
    final failed = await controller.importTransfer(merge, confirmedOverwritePaths: merge.overwritePaths);
    expect(failed.failure?.stage, TransferFailureStage.publication);
    expect(controller.documentToken, same(originalToken));
    expect(controller.library.file(id).document?.background, CanvasBackgroundKind.plain);

    store.fail = false;
    merge = await controller.previewTransferImport(candidate);
    final result = await controller.importTransfer(merge, confirmedOverwritePaths: merge.overwritePaths);
    expect(result.metadataSaved, isTrue);
    expect(store.writes.last.previous?.file(id).document?.background, CanvasBackgroundKind.plain);
    expect(store.writes.last.next.file(id).document?.background, CanvasBackgroundKind.dotGrid);
    expect(controller.documentToken, isNot(same(originalToken)));
    final replacedToken = controller.documentToken;
    await controller.create(CanvasFile(id: 'other', name: 'Other', document: CanvasLibrary.emptyDocument));
    expect(controller.documentToken, isNot(same(replacedToken)));
  });

  test('a failed flush blocks structural changes and the queue permits retry', () async {
    final id = controller.library.currentId;
    final document = _document(CanvasBackgroundKind.plain);
    controller.updateDocument(id, document);
    store.fail = true;
    await expectLater(controller.rename(id, 'Renamed'), throwsStateError);
    expect(controller.library.current.name, 'Untitled');
    expect(controller.isDirty, isTrue);
    store.fail = false;
    await controller.rename(id, 'Renamed');
    expect(controller.library.current.name, 'Renamed');
    expect(controller.library.current.document, same(document));
    expect(controller.isDirty, isFalse);
  });

  test('deletion discards writes queued for the removed file during its metadata commit', () async {
    final id = controller.library.currentId;
    final gate = Completer<void>();
    store.gate = gate;
    final deleting = controller.delete(id);
    await store.started.future;
    controller.updateDocument(id, _document(CanvasBackgroundKind.plain));
    final staleSave = controller.flush();
    gate.complete();
    await deleting;
    await staleSave;
    expect(controller.library.currentId, isNot(id));
    expect(controller.library.files, hasLength(1));
    expect(controller.isDirty, isFalse);
  });
}

// ---------- Fixtures ----------

GitHubDestination _destination() => const GitHubDestination(
  accountId: 1,
  repositoryId: 2,
  owner: 'owner',
  repository: 'repo',
  branch: 'main',
);

CanvasDocument _document(CanvasBackgroundKind background) => CanvasDocument(background: background, elements: []);

// ---------- Storage doubles ----------

class _Store implements LibraryStore {
  _Store([this.initial]);

  final CanvasLibrary? initial;
  final writes = <({CanvasLibrary? previous, CanvasLibrary next})>[];
  final started = Completer<void>();
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<CanvasLibrary?> load() async => initial;

  @override
  Future<void> save(CanvasLibrary next, {required CanvasLibrary? previous}) async {
    writes.add((previous: previous, next: next));
    final pending = gate;
    gate = null;
    if (pending != null) {
      if (!started.isCompleted) started.complete();
      await pending.future;
    }
    if (fail) throw StateError('save failed');
  }
}

class _Attachments implements AttachmentStore {
  final bytes = <String, Uint8List>{};
  bool fail = false;

  @override
  Future<void> write(String path, Uint8List value) async {
    bytes[path] = value;
    if (fail) throw StateError('attachment write failed');
  }

  @override
  Future<Uint8List> read(String path) async => bytes[path]!;

  @override
  Future<Uint8List?> readIfExists(String path) async => bytes[path];

  @override
  Future<void> delete(String path) async => bytes.remove(path);
}

class _Files implements CanvasProjectFiles {
  @override
  Future<({String name, Uint8List bytes})?> open() async => null;

  @override
  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType}) async => false;
}
