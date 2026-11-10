// Checks revision-aware saves, queued file operations, and staged attachment commits.
// Exercises the library controller independently of editor widgets and browser storage.

import 'dart:async';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
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
    expect(store.writes.single.current.document, same(first));
    expect(controller.isDirty, isTrue);
    expect(controller.snapshot.current.document, same(second));
    gate.complete();
    await saving;
    expect(store.writes.map((library) => library.current.document), [first, second]);
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

  test('ordinary file operations and edits preserve GitHub metadata', () async {
    final id = controller.library.currentId;
    final tracking = _tracking();
    final pending = _pendingTracking();
    await controller.setGitHubDestination(_destination());
    await controller.setGitHubTracking(id, tracking, pendingTracking: pending);
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
    expect(controller.library.file(id).githubTracking?.toJson(), tracking.toJson());
    expect(controller.library.file(id).githubPendingTracking?.toJson(), pending.toJson());
    expect(controller.library.file(id).githubWriteUnconfirmed, isTrue);
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

  test('last-canvas replacement checks Untitled with exact spelling', () async {
    await controller.create(const CanvasFile(id: 'lower-folder', name: 'untitled'));

    await controller.delete(controller.library.currentId);

    expect(controller.library.files.where((file) => file.name == 'Untitled' && !file.isFolder), hasLength(1));
    expect(controller.library.files.where((file) => file.name == 'untitled' && file.isFolder), hasLength(1));
  });

  test('failed tracking confirmation keeps the confirmed baseline and pending write', () async {
    final id = controller.library.currentId;
    final confirmed = _tracking();
    final pending = _pendingTracking();
    await controller.setGitHubTracking(id, confirmed, pendingTracking: pending);
    final proposed = _pendingTracking(path: 'Canvas-next.canvas');
    store.fail = true;

    await expectLater(controller.setGitHubTracking(id, proposed), throwsStateError);

    expect(controller.library.file(id).githubTracking?.toJson(), confirmed.toJson());
    expect(controller.library.file(id).githubPendingTracking?.toJson(), pending.toJson());
    store.fail = false;
  });

  test('same destination identity retains tracking, while a changed branch resets all guards', () async {
    final id = controller.library.currentId;
    final document = controller.library.current.document;
    await controller.setGitHubDestination(_destination());
    await controller.setGitHubTracking(id, _tracking(), pendingTracking: _pendingTracking());
    await controller.create(CanvasFile(id: 'other', name: 'Other', document: CanvasLibrary.emptyDocument));
    await controller.setGitHubTracking('other', _tracking(), pendingTracking: _pendingTracking());
    await controller.setGitHubDestination(
      const GitHubDestination(accountId: 1, repositoryId: 2, owner: 'renamed', repository: 'repo', branch: 'main'),
    );
    expect(controller.library.file(id).githubTracking, isNotNull);
    expect(controller.library.file(id).githubWriteUnconfirmed, isTrue);
    expect(controller.library.file(id).githubPendingTracking, isNotNull);
    expect(controller.library.file('other').githubTracking, isNotNull);
    expect(controller.library.file('other').githubWriteUnconfirmed, isTrue);

    await controller.setGitHubDestination(
      const GitHubDestination(accountId: 1, repositoryId: 2, owner: 'renamed', repository: 'repo', branch: 'next'),
    );
    expect(controller.library.file(id).githubTracking, isNull);
    expect(controller.library.file(id).githubPendingTracking, isNull);
    expect(controller.library.file(id).githubWriteUnconfirmed, isFalse);
    expect(controller.library.file('other').githubTracking, isNull);
    expect(controller.library.file('other').githubWriteUnconfirmed, isFalse);
    expect(controller.library.file(id).document, same(document));
  });

  test('GitHub canvas import stages and remaps attachments in one selected write', () async {
    final originalId = controller.library.currentId;
    await controller.setGitHubDestination(_destination());
    final confirmed = _tracking(path: 'University/Physics/Sketch.canvas');
    await controller.setGitHubTracking(
      originalId,
      confirmed,
      pendingTracking: _pendingTracking(path: 'University/Physics/Sketch-next.canvas'),
    );
    await controller.create(
      const CanvasFile(id: 'university', name: 'University'),
      openId: originalId,
    );
    store.writes.clear();
    attachments.attempted.clear();

    final id = await controller.addGitHubCanvas(
      folders: ['University', 'Physics'],
      name: 'Sketch',
      project: CanvasProject(
        document: _imageDocument(),
        attachments: {
          _path: Uint8List.fromList([2]),
        },
      ),
      tracking: GitHubCanvasTracking(
        path: 'University/Physics/Sketch.canvas',
        documentSha: 'remote-document-sha',
        attachmentShas: const {'University/Physics/attachments/original.png': 'remote-blob-sha'},
        attachmentNames: {_path: 'attachments/original.png'},
      ),
      clearPendingFileId: originalId,
    );

    final imported = controller.library.file(id);
    final localPath = canvasAttachmentPaths(imported.document!).single;
    expect(controller.library.currentId, id);
    expect(controller.library.path(id).map((file) => file.name), ['University', 'Physics', 'Sketch']);
    expect(controller.library.files.where((file) => file.isFolder && file.name == 'University'), hasLength(1));
    expect(localPath, isNot(_path));
    expect(attachments.bytes[localPath], [2]);
    expect(imported.githubTracking!.path, 'University/Physics/Sketch.canvas');
    expect(imported.githubTracking!.attachmentShas, {'University/Physics/attachments/original.png': 'remote-blob-sha'});
    expect(imported.githubTracking!.attachmentNames, {localPath: 'attachments/original.png'});
    expect(controller.library.file(originalId).githubWriteUnconfirmed, isFalse);
    expect(controller.library.file(originalId).githubTracking?.toJson(), confirmed.toJson());
    expect(controller.library.githubDestination?.toJson(), _destination().toJson());
    expect(store.writes, hasLength(1));
    expect(attachments.attempted, [localPath]);
  });

  test('GitHub import accepts case-distinct local canvas names only', () async {
    await controller.create(CanvasFile(id: 'map', name: 'Map', document: CanvasLibrary.emptyDocument));
    final project = CanvasProject(document: CanvasLibrary.emptyDocument, attachments: const {});
    final tracking = GitHubCanvasTracking(
      path: 'map.canvas',
      documentSha: 'remote-document-sha',
      attachmentShas: const {},
      attachmentNames: const {},
    );

    final importedId = await controller.addGitHubCanvas(
      folders: const [],
      name: 'map',
      project: project,
      tracking: tracking,
    );

    expect(controller.library.file(importedId).name, 'map');
    await expectLater(
      controller.addGitHubCanvas(folders: const [], name: 'Map', project: project, tracking: tracking),
      throwsFormatException,
    );
  });

  test('GitHub canvas import rejects collisions and unsafe segments without writing', () async {
    final id = controller.library.currentId;
    await controller.create(
      CanvasFile(id: 'blocked', name: 'Blocked', document: CanvasLibrary.emptyDocument),
      openId: id,
    );
    store.writes.clear();
    final project = CanvasProject(document: CanvasLibrary.emptyDocument, attachments: {});
    final tracking = GitHubCanvasTracking(
      path: 'Imported.canvas',
      documentSha: 'sha',
      attachmentShas: const {},
      attachmentNames: const {},
    );

    for (final (folders, name) in [
      (['Blocked'], 'Imported'),
      (<String>[], 'Untitled'),
      (['..'], 'Imported'),
      (['Bad/Path'], 'Imported'),
      ([r'Bad\Path'], 'Imported'),
      (['Bad\u0000Path'], 'Imported'),
      (<String>[], ''),
    ]) {
      await expectLater(
        controller.addGitHubCanvas(folders: folders, name: name, project: project, tracking: tracking),
        throwsFormatException,
      );
    }
    expect(store.writes, isEmpty);
    expect(controller.library.files, hasLength(2));
  });

  for (final failMetadata in [false, true]) {
    test('failed GitHub canvas ${failMetadata ? 'metadata' : 'attachment'} staging rolls back', () async {
      final originalId = controller.library.currentId;
      await controller.setGitHubTracking(originalId, _tracking(), pendingTracking: _pendingTracking());
      store.writes.clear();
      attachments.attempted.clear();
      attachments.deleted.clear();
      store.fail = failMetadata;
      attachments.fail = !failMetadata;
      final before = controller.library;

      await expectLater(
        controller.addGitHubCanvas(
          folders: ['New', 'Nested'],
          name: 'Imported',
          project: CanvasProject(
            document: _imageDocument(),
            attachments: {
              _path: Uint8List.fromList([2]),
            },
          ),
          tracking: GitHubCanvasTracking(
            path: 'New/Nested/Imported.canvas',
            documentSha: 'sha',
            attachmentShas: const {},
            attachmentNames: {_path: 'attachments/image.png'},
          ),
          clearPendingFileId: originalId,
        ),
        throwsStateError,
      );

      expect(identical(controller.library, before), isTrue);
      expect(controller.library.file(originalId).githubWriteUnconfirmed, isTrue);
      expect(controller.library.files.where((file) => file.name == 'New'), isEmpty);
      expect(attachments.deleted, attachments.attempted);
      expect(store.writes, hasLength(failMetadata ? 1 : 0));
      store.fail = false;
      attachments.fail = false;
    });
  }

  test('ZIP replacement clears canvas tracking and restore clears the destination', () async {
    final id = controller.library.currentId;
    await controller.setGitHubDestination(_destination());
    await controller.setGitHubTracking(id, _tracking(), pendingTracking: _pendingTracking());
    await controller.replaceCanvas(id, CanvasProject(document: _document(CanvasBackgroundKind.plain), attachments: {}));
    expect(controller.library.githubDestination, isNotNull);
    expect(controller.library.file(id).githubTracking, isNull);
    expect(controller.library.file(id).githubWriteUnconfirmed, isFalse);

    final tracked = CanvasFile(
      id: 'restored',
      name: 'Restored',
      document: CanvasLibrary.emptyDocument,
      githubTracking: _tracking(),
      githubPendingTracking: _pendingTracking(),
    );
    await controller.restore((
      library: CanvasLibrary(
        currentId: tracked.id,
        files: [tracked],
        githubDestination: _destination(),
      ),
      attachments: {},
    ));
    expect(controller.library.githubDestination, isNull);
    expect(controller.library.current.githubTracking, isNull);
    expect(controller.library.current.githubWriteUnconfirmed, isFalse);
  });

  test('the editor lifetime changes only after a successful switch or replacement', () async {
    final originalToken = controller.documentToken;
    final id = controller.library.currentId;
    controller.updateDocument(id, _document(CanvasBackgroundKind.plain));
    await controller.flush();
    await controller.rename(id, 'Renamed');
    expect(controller.documentToken, same(originalToken));
    store.fail = true;
    final project = CanvasProject(document: _document(CanvasBackgroundKind.dotGrid), attachments: {});
    await expectLater(controller.replaceCanvas(id, project), throwsStateError);
    expect(controller.documentToken, same(originalToken));
    store.fail = false;
    await controller.replaceCanvas(id, project);
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

  for (final failMetadata in [false, true]) {
    test('failed ${failMetadata ? 'metadata' : 'attachment'} staging leaves existing bytes untouched', () async {
      final id = controller.library.currentId;
      final oldBytes = Uint8List.fromList([1]);
      attachments.bytes[_path] = oldBytes;
      attachments.fail = !failMetadata;
      store.fail = failMetadata;
      final previous = controller.library;
      final project = CanvasProject(
        document: _imageDocument(),
        attachments: {
          _path: Uint8List.fromList([2]),
        },
      );
      await expectLater(controller.replaceCanvas(id, project), throwsStateError);
      expect(controller.library, same(previous));
      expect(attachments.bytes, {_path: oldBytes});
      expect(attachments.attempted, hasLength(1));
      expect(attachments.attempted.single, isNot(_path));
      expect(attachments.deleted, attachments.attempted);
      store.fail = false;
      attachments.fail = false;
      await controller.replaceCanvas(id, project);
      final path = canvasAttachmentPaths(controller.library.current.document!).single;
      expect(path, isNot(_path));
      expect(attachments.bytes[_path], oldBytes);
      expect(attachments.bytes[path], [2]);
    });
  }

  for (final restoring in [false, true]) {
    test('saves captured during ${restoring ? 'restore' : 'import'} cannot overwrite committed content', () async {
      final id = controller.library.currentId;
      final originalToken = controller.documentToken;
      controller.addListener(() {
        if (!identical(controller.documentToken, originalToken)) {
          expect(canvasAttachmentPaths(controller.snapshot.current.document!), hasLength(1));
        }
      });
      final gate = Completer<void>();
      attachments.gate = gate;
      final project = CanvasProject(
        document: _imageDocument(),
        attachments: {
          _path: Uint8List.fromList([2]),
        },
      );
      final importing = restoring
          ? controller.restore((
              library: CanvasLibrary(
                files: [CanvasFile(id: id, name: 'Restored', document: project.document)],
                currentId: id,
              ),
              attachments: project.attachments,
            ))
          : controller.replaceCanvas(id, project);
      await attachments.started.future;
      controller.updateDocument(id, _document(CanvasBackgroundKind.dotGrid));
      final staleSave = controller.flush();
      gate.complete();
      await importing;
      final imported = controller.library.current.document;
      await staleSave;
      expect(controller.library.current.document, same(imported));
      expect(canvasAttachmentPaths(imported!), hasLength(1));
      expect(controller.isDirty, isFalse);
    });
  }

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

  test('cleanup failure preserves the commit error and leaves existing attachments untouched', () async {
    final original = controller.library;
    final oldBytes = Uint8List.fromList([1]);
    attachments.bytes[_path] = oldBytes;
    attachments.failDelete = true;
    store.fail = true;
    await expectLater(
      controller.replaceCanvas(
        controller.library.currentId,
        CanvasProject(
          document: _imageDocument(),
          attachments: {
            _path: Uint8List.fromList([2]),
          },
        ),
      ),
      throwsA(isA<StateError>().having((error) => error.message, 'message', 'save failed')),
    );
    expect(controller.library, same(original));
    expect(attachments.bytes[_path], oldBytes);
    expect(attachments.deleted, attachments.attempted);
    expect(attachments.deleted, isNot(contains(_path)));
  });

  test('staging never changes existing bytes while a fresh attachment write is pending', () async {
    final oldBytes = Uint8List.fromList([1]);
    attachments.bytes[_path] = oldBytes;
    final gate = Completer<void>();
    attachments.gate = gate;
    final before = controller.library;
    final importing = controller.replaceCanvas(
      controller.library.currentId,
      CanvasProject(
        document: _imageDocument(),
        attachments: {
          _path: Uint8List.fromList([2]),
        },
      ),
    );
    await attachments.started.future;
    expect(controller.library, same(before));
    expect(attachments.bytes[_path], oldBytes);
    gate.complete();
    await importing;
    expect(attachments.bytes[_path], oldBytes);
    final imported = controller.library.current.document;
    await controller.flush();
    expect(controller.library.current.document, same(imported));
  });
}

// ---------- Fixtures ----------

const _path = 'attachments/00000000-0000-4000-8000-000000000000.png';

GitHubDestination _destination() => const GitHubDestination(
  accountId: 1,
  repositoryId: 2,
  owner: 'owner',
  repository: 'repo',
  branch: 'main',
);

GitHubCanvasTracking _tracking({String path = 'Canvas.canvas'}) => GitHubCanvasTracking(
  path: path,
  documentSha: 'document-sha',
  attachmentShas: {'${path.contains('/') ? '${path.substring(0, path.lastIndexOf('/'))}/' : ''}$_path': 'blob-sha'},
  attachmentNames: {_path: _path},
);

GitHubCanvasTracking _pendingTracking({String path = 'Canvas-pending.canvas'}) => GitHubCanvasTracking(
  path: path,
  documentSha: 'pending-document-sha',
  attachmentShas: {
    '${path.contains('/') ? '${path.substring(0, path.lastIndexOf('/'))}/' : ''}$_path': 'pending-blob-sha',
  },
  attachmentNames: {_path: _path},
);

CanvasDocument _document(CanvasBackgroundKind background) => CanvasDocument(background: background, elements: []);

CanvasDocument _imageDocument() => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [MediaElementData(id: 'image', position: Offset.zero, width: 100, url: _path)],
);

// ---------- Storage doubles ----------

class _Store implements LibraryStore {
  final writes = <CanvasLibrary>[];
  final started = Completer<void>();
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<CanvasLibrary?> load() async => null;

  @override
  Future<void> save(CanvasLibrary snapshot) async {
    writes.add(snapshot);
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
  final attempted = <String>[];
  final deleted = <String>[];
  final started = Completer<void>();
  Completer<void>? gate;
  bool fail = false;
  bool failDelete = false;

  @override
  Future<void> write(String path, Uint8List value) async {
    attempted.add(path);
    bytes[path] = value;
    final pending = gate;
    gate = null;
    if (pending != null) {
      started.complete();
      await pending.future;
    }
    if (fail) throw StateError('attachment write failed');
  }

  @override
  Future<Uint8List> read(String path) async => bytes[path]!;

  @override
  Future<Uint8List?> readIfExists(String path) async => bytes[path];

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    if (failDelete) throw StateError('cleanup failed');
    bytes.remove(path);
  }
}

class _Files implements CanvasProjectFiles {
  @override
  Future<Uint8List?> open() async => null;

  @override
  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType}) async => false;
}
