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
import 'package:elseplane/library/transfer/canvas_transfer_zip.dart';
import 'package:flutter_test/flutter_test.dart';

const _referenceA = 'attachments/00000000-0000-4000-8000-000000000001.png';
const _referenceB = 'attachments/00000000-0000-4000-8000-000000000002.png';
const _referenceC = 'attachments/00000000-0000-4000-8000-000000000003.png';

void main() {
  late _Store store;
  late _Attachments attachments;
  late _Files files;
  late LibraryController controller;
  final attachmentNotifications = <Set<String>>[];

  setUp(() async {
    store = _Store();
    attachments = _Attachments();
    files = _Files();
    attachmentNotifications.clear();
    controller = LibraryController(
      store: store,
      attachments: attachments,
      files: files,
      onAttachmentPathsChanged: attachmentNotifications.add,
    );
    await controller.load();
  });
  tearDown(() => controller.dispose());

  test('revision covers accepted edits, flushes, load, and published mutations', () async {
    final loadedRevision = controller.changeRevision;
    controller.updateDocument(controller.library.currentId, _document());
    expect(controller.changeRevision, loadedRevision + 1);
    await controller.flush();
    expect(controller.changeRevision, loadedRevision + 2);
    await controller.create(const CanvasFile(id: 'new-folder', name: 'New folder'));
    expect(controller.changeRevision, loadedRevision + 3);
    await controller.load();
    expect(controller.changeRevision, loadedRevision + 4);
  });

  test('preview and apply preserve local state and overwrite only exact paths', () async {
    await controller.create(const CanvasFile(id: 'local-folder', name: 'Local'));
    await controller.create(
      CanvasFile(id: 'local-map', name: 'Map', parentId: 'local-folder', document: _document()),
    );
    const destination = GitHubDestination(
      accountId: 1,
      repositoryId: 2,
      owner: 'owner',
      repository: 'repo',
      branch: 'main',
    );
    await controller.setGitHubDestination(destination);
    final selectedId = controller.library.currentId;
    final token = controller.documentToken;
    store.writes.clear();

    final candidate = _candidate(
      canvases: {
        'Local/Map.canvas.json': _imageDocument([_referenceA]),
        'Archive/Guide.canvas.json': _imageDocument([_referenceB]),
      },
      directories: {'Local', 'Archive'},
      attachments: {
        'Local/$_referenceA': Uint8List.fromList([1]),
        'Archive/$_referenceB': Uint8List.fromList([2]),
      },
    );
    final merge = await controller.previewTransferImport(candidate);
    expect(merge.overwritePaths, {'Local/Map.canvas.json'});
    expect(merge.expectedChangeRevision, controller.changeRevision);

    final result = await controller.importTransfer(merge, confirmedOverwritePaths: merge.overwritePaths);

    expect(result.failure, isNull);
    expect(result.metadataSaved, isTrue);
    expect(result.writtenImagePaths, ['Archive/$_referenceB', 'Local/$_referenceA']);
    expect(attachments.attempted, result.writtenImagePaths);
    expect(attachmentNotifications, [
      {...result.writtenImagePaths},
    ]);
    expect(store.writes, hasLength(1));
    expect(controller.library.currentId, selectedId);
    expect(controller.library.githubDestination?.toJson(), destination.toJson());
    expect(controller.library.file('local-map').document, same(candidate.canvases['Local/Map.canvas.json']));
    expect(controller.library.file('local-folder').id, 'local-folder');
    expect(
      controller.library.file(controller.library.files.singleWhere((file) => file.name == 'Archive').id).isFolder,
      isTrue,
    );
    expect(controller.library.files.any((file) => file.id == 'local-map' && file.name == 'Guide'), isFalse);
    expect(controller.documentToken, isNot(same(token)));
    expect(controller.library.files.any((file) => file.id == selectedId), isTrue);
  });

  test('wrong confirmation and stale preview return preparation failures before import writes', () async {
    final candidate = _candidate(
      canvases: {
        'Imported.canvas.json': _imageDocument([_referenceA]),
      },
      attachments: {
        _referenceA: Uint8List.fromList([4]),
      },
    );
    final merge = await controller.previewTransferImport(candidate);
    final wrong = await controller.importTransfer(merge, confirmedOverwritePaths: {'unexpected.canvas.json'});
    expect(wrong.failure?.stage, TransferFailureStage.preparation);
    expect(attachments.attempted, isEmpty);
    expect(store.writes, isEmpty);

    final staleMerge = await controller.previewTransferImport(candidate);
    controller.updateDocument(controller.library.currentId, _document(CanvasBackgroundKind.dotGrid));
    final stale = await controller.importTransfer(staleMerge, confirmedOverwritePaths: const {});
    expect(stale.failure?.stage, TransferFailureStage.preparation);
    expect(stale.writtenImagePaths, isEmpty);
    expect(attachments.attempted, isEmpty);
    expect(controller.library.files.any((file) => file.name == 'Imported'), isFalse);
  });

  test('image failure stops in sorted order and reports only closed writes', () async {
    final candidate = _candidate(
      canvases: {
        'Imported.canvas.json': _imageDocument([_referenceC, _referenceA, _referenceB]),
      },
      attachments: {
        _referenceC: Uint8List.fromList([3]),
        _referenceA: Uint8List.fromList([1]),
        _referenceB: Uint8List.fromList([2]),
      },
    );
    final merge = await controller.previewTransferImport(candidate);
    attachments.failPaths.add(_referenceB);

    final result = await controller.importTransfer(merge, confirmedOverwritePaths: const {});

    expect(attachments.attempted, [_referenceA, _referenceB]);
    expect(result.writtenImagePaths, [_referenceA]);
    expect(result.metadataSaved, isFalse);
    expect(result.failure?.stage, TransferFailureStage.imageWrite);
    expect(result.failure?.path, _referenceB);
    expect(result.failure?.reason, 'Image write failed');
    expect(store.writes, isEmpty);
    expect(attachmentNotifications, [
      {_referenceA, _referenceB},
    ]);
  });

  test('a pending edit during image writes invalidates before metadata save', () async {
    final candidate = _candidate(
      canvases: {
        'Imported.canvas.json': _imageDocument([_referenceA]),
      },
      attachments: {
        _referenceA: Uint8List.fromList([1]),
      },
    );
    final merge = await controller.previewTransferImport(candidate);
    final gate = Completer<void>();
    attachments
      ..writeGate = gate
      ..writeStarted = Completer<void>();

    final importing = controller.importTransfer(merge, confirmedOverwritePaths: const {});
    await attachments.writeStarted!.future;
    controller.updateDocument(controller.library.currentId, _document(CanvasBackgroundKind.dotGrid));
    gate.complete();
    final result = await importing;

    expect(result.failure?.stage, TransferFailureStage.publication);
    expect(result.writtenImagePaths, [_referenceA]);
    expect(result.metadataSaved, isFalse);
    expect(store.writes, isEmpty);
    expect(controller.library.files.any((file) => file.name == 'Imported'), isFalse);
    expect(attachmentNotifications, [
      {_referenceA},
    ]);
    await controller.flush();
  });

  test('edits during a failed metadata save remain pending for retry', () async {
    final currentId = controller.library.currentId;
    final originalToken = controller.documentToken;
    final candidate = _candidate(
      canvases: {
        'Untitled.canvas.json': _imageDocument([_referenceA]),
      },
      attachments: {
        _referenceA: Uint8List.fromList([1]),
      },
    );
    final merge = await controller.previewTransferImport(candidate);
    final gate = Completer<void>();
    store
      ..saveGate = gate
      ..saveStarted = Completer<void>()
      ..fail = true;

    final importing = controller.importTransfer(merge, confirmedOverwritePaths: merge.overwritePaths);
    await store.saveStarted!.future;
    controller.updateDocument(currentId, _document(CanvasBackgroundKind.dotGrid));
    gate.complete();
    final result = await importing;

    expect(result.failure?.stage, TransferFailureStage.publication);
    expect(result.failure?.reason, 'Library save failed');
    expect(result.writtenImagePaths, [_referenceA]);
    expect(controller.documentToken, same(originalToken));
    expect(controller.library.file(currentId).document, isNot(same(candidate.canvases['Untitled.canvas.json'])));
    expect(controller.isDirty, isTrue);
    expect(attachmentNotifications, [
      {_referenceA},
    ]);
    store.fail = false;
    await controller.flush();
    expect(controller.isDirty, isFalse);
    expect(controller.library.file(currentId).document?.background, CanvasBackgroundKind.dotGrid);
  });

  test('moving canvases copies images and same-parent rename copies nothing', () async {
    await controller.create(const CanvasFile(id: 'source', name: 'Source'));
    await controller.create(const CanvasFile(id: 'destination', name: 'Destination'));
    await controller.create(
      CanvasFile(id: 'map', name: 'Map', parentId: 'source', document: _imageDocument([_referenceA])),
    );
    const sourcePath = 'Source/$_referenceA';
    const destinationPath = 'Destination/$_referenceA';
    attachments.bytes[sourcePath] = Uint8List.fromList([9]);
    attachments.attempted.clear();
    store.writes.clear();

    await controller.move('map', parentId: 'destination');
    expect(attachments.bytes[sourcePath], [9]);
    expect(attachments.bytes[destinationPath], [9]);
    expect(attachments.attempted, [destinationPath]);
    expect(attachmentNotifications, [
      {destinationPath},
    ]);
    expect(controller.library.parentDirectory('map'), 'Destination');

    await controller.rename('map', 'Renamed');
    expect(attachments.attempted, [destinationPath]);
    expect(attachmentNotifications, [
      {destinationPath},
    ]);
  });

  test('current and library exports use one root-relative transfer ZIP', () async {
    await controller.create(const CanvasFile(id: 'projects', name: 'Projects'));
    await controller.create(
      CanvasFile(id: 'map', name: 'Map', parentId: 'projects', document: _imageDocument([_referenceA])),
    );
    attachments.bytes['Projects/$_referenceA'] = Uint8List.fromList([7]);

    expect(await controller.exportCanvas('map'), isFalse);
    expect(files.suggestedName, 'canvas.elseplane.zip');
    expect(files.mimeType, 'application/zip');
    final current = await decodeTransfer(ZipTransferSource(files.savedBytes!));
    expect(current.canvases.keys.toSet(), {'Projects/Map.canvas.json'});
    expect(current.directories, {'Projects'});
    expect(current.attachments.keys, {'Projects/$_referenceA'});

    expect(await controller.exportLibrary(), isFalse);
    expect(files.suggestedName, 'library.elseplane.zip');
    final whole = await decodeTransfer(ZipTransferSource(files.savedBytes!));
    expect(whole.canvases.keys.toSet(), {'Untitled.canvas.json', 'Projects/Map.canvas.json'});
    expect(whole.attachments.keys, {'Projects/$_referenceA'});
  });

  test('folder rename keeps source bytes and invalidates attempted copies after save failure', () async {
    await controller.create(const CanvasFile(id: 'projects', name: 'Projects'));
    await controller.create(
      CanvasFile(id: 'map', name: 'Map', parentId: 'projects', document: _imageDocument([_referenceA])),
    );
    const sourcePath = 'Projects/$_referenceA';
    const destinationPath = 'Work/$_referenceA';
    attachments.bytes[sourcePath] = Uint8List.fromList([8]);
    store.fail = true;

    await expectLater(controller.rename('projects', 'Work'), throwsStateError);

    expect(controller.library.file('projects').name, 'Projects');
    expect(attachments.bytes[sourcePath], [8]);
    expect(attachments.bytes[destinationPath], [8]);
    expect(attachmentNotifications, [
      {destinationPath},
    ]);
  });

  test('move preflights different destination bytes before writing', () async {
    await controller.create(const CanvasFile(id: 'source', name: 'Source'));
    await controller.create(const CanvasFile(id: 'destination', name: 'Destination'));
    await controller.create(
      CanvasFile(id: 'map', name: 'Map', parentId: 'source', document: _imageDocument([_referenceA])),
    );
    attachments.bytes['Source/$_referenceA'] = Uint8List.fromList([1]);
    attachments.bytes['Destination/$_referenceA'] = Uint8List.fromList([2]);

    await expectLater(controller.move('map', parentId: 'destination'), throwsFormatException);

    expect(attachments.attempted, isEmpty);
    expect(controller.library.parentDirectory('map'), 'Source');
    expect(attachmentNotifications, isEmpty);
  });
}

TransferImport _candidate({
  required Map<String, CanvasDocument> canvases,
  Map<String, Uint8List> attachments = const {},
  Set<String> directories = const {},
}) => TransferImport(
  canvases: canvases,
  attachments: attachments,
  directories: directories,
  skippedCanvases: const [],
);

CanvasDocument _document([CanvasBackgroundKind background = CanvasBackgroundKind.plain]) =>
    CanvasDocument(background: background, elements: []);

CanvasDocument _imageDocument(List<String> references) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    for (var index = 0; index < references.length; index++)
      MediaElementData(id: 'image-$index', position: Offset.zero, width: 120, url: references[index]),
  ],
);

class _Store implements LibraryStore {
  final writes = <CanvasLibrary>[];
  Completer<void>? saveGate;
  Completer<void>? saveStarted;
  bool fail = false;

  @override
  Future<CanvasLibrary?> load() async => null;

  @override
  Future<void> save(CanvasLibrary next, {required CanvasLibrary? previous}) async {
    writes.add(next);
    final gate = saveGate;
    saveGate = null;
    if (gate != null) {
      saveStarted?.complete();
      await gate.future;
    }
    if (fail) throw StateError('save failed');
  }
}

class _Attachments implements AttachmentStore {
  final bytes = <String, Uint8List>{};
  final attempted = <String>[];
  final completed = <String>[];
  final failPaths = <String>{};
  Completer<void>? writeGate;
  Completer<void>? writeStarted;

  @override
  Future<void> write(String path, Uint8List value) async {
    attempted.add(path);
    bytes[path] = Uint8List.fromList(value);
    final gate = writeGate;
    writeGate = null;
    if (gate != null) {
      writeStarted?.complete();
      await gate.future;
    }
    if (failPaths.contains(path)) throw StateError('write failed');
    completed.add(path);
  }

  @override
  Future<void> delete(String path) async {
    bytes.remove(path);
  }

  @override
  Future<Uint8List> read(String path) async => bytes[path]!;

  @override
  Future<Uint8List?> readIfExists(String path) async => bytes[path];
}

class _Files implements CanvasProjectFiles {
  Uint8List? savedBytes;
  String? suggestedName;
  String? mimeType;

  @override
  Future<({String name, Uint8List bytes})?> open() async => null;

  @override
  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType}) async {
    savedBytes = bytes;
    this.suggestedName = suggestedName;
    this.mimeType = mimeType;
    return false;
  }
}
