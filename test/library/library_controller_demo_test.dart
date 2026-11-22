import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/debug/demo_canvas.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_asset_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installDemoAssetFixture);

  late _Store store;
  late _Attachments attachments;
  late LibraryController controller;
  final invalidations = <Set<String>>[];

  setUp(() async {
    store = _Store();
    attachments = _Attachments();
    invalidations.clear();
    controller = LibraryController(
      store: store,
      attachments: attachments,
      files: _Files(),
      onAttachmentPathsChanged: invalidations.add,
    );
    await controller.load();
  });
  tearDown(() => controller.dispose());

  test('does not read the demo during library load', () {
    expect(demoAssetReadCount, 0);
  });

  test('creates and opens uniquely named demos with exact image keys', () async {
    final firstId = await controller.createDemo();
    expect(controller.library.file(firstId).name, 'Demo');
    expect(controller.library.currentId, firstId);
    expect(store.writes, hasLength(1));
    expect(attachments.attempted, [demoImagePath]);
    expect(invalidations, [
      {demoImagePath},
    ]);

    final secondId = await controller.createDemo();
    expect(controller.library.file(secondId).name, 'Demo 2');
    expect(controller.library.currentId, secondId);
    expect(store.writes, hasLength(2));
    expect(controller.library.current.document!.elements.whereType<MediaElementData>().single.url, demoImagePath);

    final source = await loadDemoCanvas();
    expect(attachments.bytes[demoImagePath], source.attachments[demoImagePath]);
  });

  test('failed image close keeps library unpublished and invalidates attempted key', () async {
    final before = controller.library;
    attachments.fail = true;

    await expectLater(controller.createDemo(), throwsStateError);

    expect(controller.library, same(before));
    expect(store.writes, isEmpty);
    expect(attachments.attempted, [demoImagePath]);
    expect(invalidations, [
      {demoImagePath},
    ]);
    expect((await loadDemoCanvas()).attachments[demoImagePath], demoImageBytes);
  });

  test('failed metadata save leaves demo bytes but does not publish the canvas', () async {
    final before = controller.library;
    store.fail = true;

    await expectLater(controller.createDemo(), throwsStateError);

    expect(controller.library, same(before));
    expect(store.writes, hasLength(1));
    expect(attachments.attempted, [demoImagePath]);
    expect(attachments.bytes[demoImagePath], demoImageBytes);
    expect(invalidations, [
      {demoImagePath},
    ]);
  });
}

class _Store implements LibraryStore {
  final writes = <CanvasLibrary>[];
  bool fail = false;

  @override
  Future<CanvasLibrary?> load() async => null;

  @override
  Future<void> save(CanvasLibrary next, {required CanvasLibrary? previous}) async {
    writes.add(next);
    if (fail) throw StateError('save failed');
  }
}

class _Attachments implements AttachmentStore {
  final bytes = <String, Uint8List>{};
  final attempted = <String>[];
  bool fail = false;

  @override
  Future<void> write(String path, Uint8List value) async {
    attempted.add(path);
    bytes[path] = Uint8List.fromList(value);
    if (fail) throw StateError('write failed');
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
