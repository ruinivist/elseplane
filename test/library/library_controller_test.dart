// Checks revision-aware saves, queued file operations, and staged attachment commits.
// Exercises the library controller independently of editor widgets and browser storage.

import 'dart:async';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
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
