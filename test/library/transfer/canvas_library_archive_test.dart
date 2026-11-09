// Verifies whole-library ZIP structure and restore validation.
// Exercises folder hierarchy, shared images, and malformed backups.

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/transfer/canvas_library_archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../canvas/test_helpers.dart';

// ---------- Tests ----------

void main() {
  test('round trip keeps hierarchy, empty folders, names, and shared images', () async {
    final library = CanvasLibrary(
      currentId: 'nested',
      files: [
        const CanvasFile(id: 'folder', name: 'Notes.json'),
        const CanvasFile(id: 'empty', name: 'Empty', parentId: 'folder'),
        CanvasFile(id: 'root', name: 'Notes', document: _document('root')),
        CanvasFile(id: 'nested', name: 'Sketch', parentId: 'folder', document: _document('nested')),
      ],
    );
    final bytes = await encodeCanvasLibraryArchive(library, TestAttachmentStore({_path: onePixelPngBytes}));
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(
      zip.map((entry) => entry.name),
      containsAll([
        'library/Notes.json/',
        'library/Notes.json/Empty/',
        'library/Notes (canvas 2).json',
        'library/Notes.json/Sketch.json',
        _path,
      ]),
    );
    expect(zip.where((entry) => entry.name == _path), hasLength(1));

    final restored = await decodeCanvasLibraryArchive(bytes);
    expect(restored.library.files.where((file) => file.isFolder).map((file) => file.name), ['Notes.json', 'Empty']);
    expect(restored.library.files.where((file) => !file.isFolder).map((file) => file.name), ['Notes', 'Sketch']);
    expect(restored.library.path(restored.library.files.last.id).map((file) => file.name), ['Notes.json', 'Sketch']);
    expect(restored.library.current.name, 'Notes');
    expect(restored.attachments[_path], onePixelPngBytes);
  });

  test('library backup and restore preserve plain shape text', () async {
    const shapeText = '  日本語 ☃️\n\n![literal]($_literalPath)\n  ';
    final document = _document('canvas').withElements((elements) => elements.add(_shape(shapeText)));
    final library = CanvasLibrary(
      files: [CanvasFile(id: 'canvas', name: 'Canvas', document: document)],
      currentId: 'canvas',
    );
    final store = _RecordingAttachmentStore({_path: onePixelPngBytes, _literalPath: onePixelPngBytes});

    final bytes = await encodeCanvasLibraryArchive(library, store);
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.map((entry) => entry.name), ['library/', 'library/Canvas.json', 'attachments/', _path]);
    expect(store.readPaths, [_path]);

    final restored = await decodeCanvasLibraryArchive(bytes);
    expect(restored.library.current.document!.elements.whereType<ShapeElementData>().single.text, shapeText);
    expect(restored.attachments.keys, {_path});
  });

  test('backup and restore reject corrupt referenced images', () async {
    final source = CanvasLibrary(
      files: [CanvasFile(id: 'canvas', name: 'Canvas', document: _document('one'))],
      currentId: 'canvas',
    );
    final bytes = Uint8List.fromList([1, 2, 3]);
    final invalidImage = throwsA(
      isA<FormatException>().having((error) => error.message, 'message', contains('Invalid encoded image')),
    );

    await expectLater(encodeCanvasLibraryArchive(source, TestAttachmentStore({_path: bytes})), invalidImage);

    final content = utf8.encode(
      jsonEncode({'version': 1, 'name': 'Canvas', 'document': source.current.document!.toJson()}),
    );
    final archive = Archive()
      ..add(ArchiveFile.directory('library/'))
      ..add(ArchiveFile.bytes('library/Canvas.json', content))
      ..add(ArchiveFile.directory('attachments/'))
      ..add(ArchiveFile.bytes(_path, bytes));
    await expectLater(decodeCanvasLibraryArchive(ZipEncoder().encodeBytes(archive)), invalidImage);
  });

  test('rejects missing attachments and duplicate ZIP paths', () async {
    final source = CanvasLibrary(
      files: [CanvasFile(id: 'canvas', name: 'Canvas', document: _document('one'))],
      currentId: 'canvas',
    );
    await expectLater(encodeCanvasLibraryArchive(source, TestAttachmentStore()), throwsFormatException);

    final content = utf8.encode(
      jsonEncode({
        'version': 1,
        'name': 'Canvas',
        'document': _document('one').toJson(),
      }),
    );
    final archive = Archive()
      ..add(ArchiveFile.directory('library/'))
      ..add(ArchiveFile.bytes('library/Canvas.json', content));
    await expectLater(decodeCanvasLibraryArchive(ZipEncoder().encodeBytes(archive)), throwsFormatException);

    archive.add(ArchiveFile.bytes('library/Canvas.json', content));
    await expectLater(decodeCanvasLibraryArchive(ZipEncoder().encodeBytes(archive)), throwsFormatException);
  });

  test('library archives preserve raw media sources and referenced attachments', () async {
    final sources = [
      '  example.com/articles/design  ',
      'javascript:alert(1)',
      'https:///missing-host',
      _path,
    ];
    final decoded = await decodeCanvasLibraryArchive(await _mediaArchive(sources));
    expect(
      decoded.library.current.document!.elements.whereType<MediaElementData>().map((element) => element.url),
      sources,
    );
    expect(decoded.attachments[_path], onePixelPngBytes);
  });
}

// ---------- Fixtures ----------

const _path = 'attachments/00000000-0000-4000-8000-000000000000.png';
const _literalPath = 'attachments/00000001-0000-4000-8000-000000000000.png';

CanvasDocument _document(String id) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    MediaElementData(id: id, position: Offset.zero, width: 120, url: _path),
  ],
);

ShapeElementData _shape(String text) => ShapeElementData(
  id: 'shape-1',
  kind: ShapeKind.rectangle,
  position: const Offset(100, 200),
  size: const Size(160, 100),
  strokeColor: const Color(0xff000000),
  fillColor: null,
  strokeWidth: 2,
  text: text,
);

class _RecordingAttachmentStore extends TestAttachmentStore {
  _RecordingAttachmentStore(super.initial);

  final readPaths = <String>[];

  @override
  Future<Uint8List?> readIfExists(String path) async {
    readPaths.add(path);
    return await super.readIfExists(path);
  }
}

Future<Uint8List> _mediaArchive(List<String> sources) {
  final document = CanvasDocument(
    background: CanvasBackgroundKind.plain,
    elements: [
      for (var index = 0; index < sources.length; index++)
        MediaElementData(id: 'media-$index', position: Offset.zero, width: 120, url: sources[index]),
    ],
  );
  final library = CanvasLibrary(
    files: [CanvasFile(id: 'canvas', name: 'Canvas', document: document)],
    currentId: 'canvas',
  );
  return encodeCanvasLibraryArchive(library, TestAttachmentStore({_path: onePixelPngBytes}));
}
