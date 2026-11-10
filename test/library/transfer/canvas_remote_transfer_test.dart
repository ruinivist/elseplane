// Verifies GitHub canvas transfer validation and mirrored repository paths.

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:elseplane/library/transfer/canvas_remote_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes versioned pretty JSON and prepares only referenced images', () async {
    final document = _document(_path(0));
    final store = _CountingStore({_path(0): _onePixelPng, _path(1): _onePixelPng});

    final project = await prepareCanvasRemoteTransfer(document, store);

    expect(
      encodeRemoteCanvasDocument(document),
      utf8.encode(const JsonEncoder.withIndent('  ').convert(document.toJson())),
    );
    expect(project.attachments.keys, {_path(0)});
    expect(store.readPaths, [_path(0)]);
    final decoded = await decodeCanvasRemoteTransfer(encodeRemoteCanvasDocument(document), project.attachments);
    expect(decoded.document.toJson(), document.toJson());
    expect(decoded.attachments.keys, {_path(0)});
  });

  test('remote decoding rejects mismatched references, invalid images, and oversized documents', () async {
    final document = _document(_path(0));
    final bytes = encodeRemoteCanvasDocument(document);
    await expectLater(decodeCanvasRemoteTransfer(bytes, {}), throwsFormatException);
    await expectLater(
      decodeCanvasRemoteTransfer(bytes, {
        _path(0): Uint8List.fromList([1, 2, 3]),
      }),
      throwsFormatException,
    );
    await expectLater(
      decodeCanvasRemoteTransfer(Uint8List(canvasProjectMaximumBytes + 1), {}),
      throwsFormatException,
    );
  });

  test('mirrors safe root and nested paths with spaces and Unicode', () {
    final library = CanvasLibrary(
      currentId: 'root',
      files: [
        CanvasFile(id: 'root', name: 'Maths Notes', document: CanvasLibrary.emptyDocument),
        const CanvasFile(id: 'university', name: 'University 🌱'),
        CanvasFile(
          id: 'nested',
          name: 'Physics Notes',
          parentId: 'university',
          document: CanvasLibrary.emptyDocument,
        ),
      ],
    );

    expect(canvasRemotePath(library, 'root'), 'Maths Notes.canvas');
    expect(canvasRemotePath(library, 'nested'), 'University 🌱/Physics Notes.canvas');
  });

  test('rejects unsafe segments, reserved attachment folders, and mirrored file-folder collisions', () {
    CanvasLibrary library(List<CanvasFile> files, String currentId) =>
        CanvasLibrary(files: files, currentId: currentId);

    expect(
      () => canvasRemotePath(
        library([CanvasFile(id: 'bad', name: '..', document: CanvasLibrary.emptyDocument)], 'bad'),
        'bad',
      ),
      throwsFormatException,
    );
    expect(
      () => canvasRemotePath(
        library([
          const CanvasFile(id: 'folder', name: 'attachments'),
          CanvasFile(id: 'canvas', name: 'Notes', document: CanvasLibrary.emptyDocument),
        ], 'canvas'),
        'canvas',
      ),
      throwsFormatException,
    );
    expect(
      () => canvasRemotePath(
        library([
          CanvasFile(id: 'canvas', name: 'Course', document: CanvasLibrary.emptyDocument),
          const CanvasFile(id: 'folder', name: 'Course.canvas'),
        ], 'canvas'),
        'canvas',
      ),
      throwsFormatException,
    );
    expect(
      () => canvasRemotePath(
        library([
          CanvasFile(id: 'root', name: 'Course', document: CanvasLibrary.emptyDocument),
          const CanvasFile(id: 'folder', name: 'Course.canvas'),
          CanvasFile(id: 'nested', name: 'Child', parentId: 'folder', document: CanvasLibrary.emptyDocument),
        ], 'nested'),
        'nested',
      ),
      throwsFormatException,
    );
  });
}

String _path(int index) => 'attachments/0000000$index-0000-4000-8000-000000000000.png';

final _onePixelPng = Uint8List.fromList(
  base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
);

CanvasDocument _document(String path) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [MediaElementData(id: 'image', position: Offset.zero, width: 120, url: path)],
);

class _CountingStore implements AttachmentStore {
  _CountingStore(this.files);

  final Map<String, Uint8List> files;
  final readPaths = <String>[];

  @override
  Future<Uint8List> read(String path) async {
    readPaths.add(path);
    return files[path]!;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async => throw UnimplementedError();

  @override
  Future<void> delete(String path) async => throw UnimplementedError();

  @override
  Future<Uint8List?> readIfExists(String path) async => files[path];
}
