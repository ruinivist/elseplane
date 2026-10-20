// Verifies whole-library ZIP structure and restore validation.
// Exercises folder hierarchy, shared images, and malformed backups.

@TestOn('browser')
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/persistence/canvas_library.dart';
import 'package:elseplane/canvas/persistence/canvas_library_archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

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
}

// ---------- Fixtures ----------

const _path = 'attachments/00000000-0000-4000-8000-000000000000.png';

CanvasDocument _document(String id) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    MediaElementData(id: id, position: Offset.zero, width: 120, url: _path),
  ],
);
