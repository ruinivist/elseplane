import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageReference = 'attachments/123e4567-e89b-42d3-a456-426614174000.png';
  const imageA = 'A/$imageReference';
  const imageB = 'B/$imageReference';

  test('encodes captured current and whole-library scopes with full parent keys', () async {
    final a = _document(imageReference, 'a');
    final b = _document(imageReference, 'b');
    final library = CanvasLibrary(
      currentId: 'b',
      files: [
        const CanvasFile(id: 'a-folder', name: 'A'),
        CanvasFile(id: 'a', name: 'Map', parentId: 'a-folder', document: a),
        const CanvasFile(id: 'b-folder', name: 'B'),
        CanvasFile(id: 'b', name: 'Map', parentId: 'b-folder', document: b),
        const CanvasFile(id: 'empty', name: 'Empty', parentId: 'b-folder'),
      ],
    );
    final store = _MemoryAttachments({
      imageA: [1],
      imageB: [2],
    });

    final current = await encodeTransfer(library, store, TransferScope.currentCanvas);
    expect(current.files.keys, {'B/Map.canvas.json', imageB});
    expect(current.directories, {'B'});
    expect(jsonDecode(utf8.decode(current.files['B/Map.canvas.json']!)), b.toJson());

    final whole = await encodeTransfer(library, store, TransferScope.wholeLibrary);
    expect(whole.files.keys, {'A/Map.canvas.json', imageA, 'B/Map.canvas.json', imageB});
    expect(whole.directories, {'A', 'B', 'B/Empty'});
    expect(store.reads, unorderedEquals([imageB, imageA, imageB]));
  });

  test('missing attachments remain references and storage failures propagate', () async {
    final tree = await encodeTransfer(
      CanvasLibrary.initial(_document(imageReference, 'one')),
      _MemoryAttachments(),
      TransferScope.currentCanvas,
    );
    expect(tree.files.keys, {'Untitled.canvas.json'});
    expect(
      () => encodeTransfer(
        CanvasLibrary.initial(_document(imageReference, 'two')),
        _MemoryAttachments()..failReads = true,
        TransferScope.currentCanvas,
      ),
      throwsStateError,
    );
  });

  test('decodes valid documents, preserves empty folders, and stores only eligible images', () async {
    final valid = _document(imageReference, 'valid');
    final skipped = _document('attachments/123e4567-e89b-42d3-a456-426614174001.png', 'skipped');
    final source = _MemorySource(
      files: {
        'Projects/Map.canvas.json': _json(valid.toJson()),
        'Projects/Broken.canvas.json': Uint8List.fromList([0xff]),
        'Projects/Unsupported.canvas.json': _json({
          ..._document('attachments/123e4567-e89b-42d3-a456-426614174001.png', 'unsupported').toJson(),
          'version': CanvasDocument.version - 1,
        }),
        'Projects/attachments/123e4567-e89b-42d3-a456-426614174000.png': Uint8List.fromList([1, 2, 3]),
        'Projects/attachments/123e4567-e89b-42d3-a456-426614174001.png': Uint8List.fromList([4]),
        'Unused.canvas.json': _json(skipped.toJson()),
        'README': Uint8List.fromList([5]),
        '.git/config': Uint8List.fromList([6]),
        '.git/Hidden.canvas.json': _json(valid.toJson()),
      },
      directories: {'Projects/Empty', '.git'},
    );

    final decoded = await decodeTransfer(source);
    expect(decoded.canvases.keys, {'Projects/Map.canvas.json', 'Unused.canvas.json'});
    expect(decoded.attachments.keys, {'Projects/attachments/123e4567-e89b-42d3-a456-426614174000.png'});
    expect(decoded.attachments.values.single, [1, 2, 3]);
    expect(decoded.directories, {'Projects', 'Projects/Empty'});
    expect(decoded.skippedCanvases.map((issue) => (issue.path, issue.reason)), [
      ('Projects/Broken.canvas.json', 'Invalid UTF-8'),
      ('Projects/Unsupported.canvas.json', 'Unsupported canvas schema'),
    ]);
    expect(source.reads, contains('Projects/attachments/123e4567-e89b-42d3-a456-426614174001.png'));
    expect(source.reads, isNot(contains('.git/config')));
    expect(source.reads, isNot(contains('README')));
  });

  test('preserves raw media sources and corrupt referenced image bytes', () async {
    const rawSources = [
      '  example.com/articles/design  ',
      'javascript:alert(1)',
      'https:///missing-host',
      imageReference,
    ];
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        for (var index = 0; index < rawSources.length; index++)
          MediaElementData(id: 'media-$index', position: Offset.zero, width: 120, url: rawSources[index]),
      ],
    );
    final corruptImageBytes = Uint8List.fromList([1, 2, 3]);

    final decoded = await decodeTransfer(
      _MemorySource(
        files: {
          'Canvas.canvas.json': _json(document.toJson()),
          imageReference: corruptImageBytes,
        },
      ),
    );

    expect(
      decoded.canvases['Canvas.canvas.json']!.elements.whereType<MediaElementData>().map((element) => element.url),
      rawSources,
    );
    expect(decoded.attachments[imageReference], corruptImageBytes);
  });

  test('skips malformed JSON and schemas with fixed reasons', () async {
    final candidate = await decodeTransfer(
      _MemorySource(
        files: {
          'Json.canvas.json': Uint8List.fromList(utf8.encode('{')),
          'Malformed.canvas.json': _json({
            'version': CanvasDocument.version,
            'background': 'unknown',
            'elements': <Object?>[],
          }),
          'Old.canvas.json': _json({'version': CanvasDocument.version - 1}),
        },
      ),
    );
    expect(candidate.canvases, isEmpty);
    expect(candidate.skippedCanvases.map((issue) => issue.reason), [
      'Invalid JSON',
      'Invalid canvas schema',
      'Unsupported canvas schema',
    ]);
  });

  test('validates all source paths and sizes before reading documents', () async {
    final invalidPath = _MemorySource(files: {'../Map.canvas.json': Uint8List(0)});
    await expectLater(decodeTransfer(invalidPath), throwsFormatException);
    expect(invalidPath.reads, isEmpty);

    final badCanvasLocation = _MemorySource(
      files: {'attachments/Map.canvas.json': _json(_document('', 'bad').toJson())},
    );
    await expectLater(decodeTransfer(badCanvasLocation), throwsFormatException);
    expect(badCanvasLocation.reads, isEmpty);

    final oversized = _MemorySource(
      files: {'Map.canvas.json': Uint8List(1)},
      declaredSizes: {'Map.canvas.json': canvasTransferMaximumBytes + 1},
    );
    await expectLater(decodeTransfer(oversized), throwsFormatException);
    expect(oversized.reads, isEmpty);

    final oversizedImage = _MemorySource(
      files: {'attachments/123e4567-e89b-42d3-a456-426614174000.png': Uint8List(1)},
      declaredSizes: {'attachments/123e4567-e89b-42d3-a456-426614174000.png': attachmentMaximumBytes + 1},
    );
    await expectLater(decodeTransfer(oversizedImage), throwsFormatException);
    expect(oversizedImage.reads, isEmpty);

    final invalidImagePath = _MemorySource(files: {'attachments/not-an-image.png': Uint8List(0)});
    await expectLater(decodeTransfer(invalidImagePath), throwsFormatException);
    expect(invalidImagePath.reads, isEmpty);

    final missingSize = _MemorySource(files: {'README': Uint8List(0)}, omitSizes: true);
    await expectLater(decodeTransfer(missingSize), throwsFormatException);
    expect(missingSize.reads, isEmpty);
  });

  test('source read and declared-size failures are not skipped documents', () async {
    final sourceFailure = _MemorySource(
      files: {'Map.canvas.json': _json(_document('', 'read').toJson())},
    )..failReads = true;
    await expectLater(decodeTransfer(sourceFailure), throwsStateError);

    final mismatch = _MemorySource(
      files: {'Map.canvas.json': _json(_document('', 'size').toJson())},
      declaredSizes: {'Map.canvas.json': 1},
    );
    await expectLater(decodeTransfer(mismatch), throwsFormatException);
  });

  test('standalone source strips only the final suffix and validates its basename', () async {
    final source = StandaloneCanvasTransferSource(
      name: 'Résumé.canvas.json.canvas.json',
      bytes: _json(_document('', 'standalone').toJson()),
    );
    expect((await source.entries()).single.path, 'Résumé.canvas.json.canvas.json');
    expect(
      () => StandaloneCanvasTransferSource(name: '../Map.canvas.json', bytes: Uint8List(0)),
      throwsFormatException,
    );
    expect(
      () => StandaloneCanvasTransferSource(name: '.canvas.json', bytes: Uint8List(0)),
      throwsFormatException,
    );
  });
}

Uint8List _json(Object? value) => Uint8List.fromList(utf8.encode(jsonEncode(value)));

CanvasDocument _document(String reference, String id) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    MediaElementData(id: id, position: Offset.zero, width: 300, url: reference),
  ],
);

class _MemoryAttachments implements AttachmentStore {
  _MemoryAttachments([Map<String, List<int>> initial = const {}])
    : files = {
        for (final entry in initial.entries) entry.key: Uint8List.fromList(entry.value),
      };

  final Map<String, Uint8List> files;
  final List<String> reads = [];
  bool failReads = false;

  @override
  Future<Uint8List?> readIfExists(String path) async {
    reads.add(path);
    if (failReads) throw StateError('read failed');
    return files[path];
  }

  @override
  Future<Uint8List> read(String path) async => files[path]!;

  @override
  Future<void> write(String path, Uint8List bytes) async => files[path] = bytes;

  @override
  Future<void> delete(String path) async => files.remove(path);
}

class _MemorySource implements TransferSource {
  _MemorySource({
    required this.files,
    this.directories = const {},
    this.declaredSizes = const {},
    this.omitSizes = false,
  });

  final Map<String, Uint8List> files;
  final Set<String> directories;
  final Map<String, int> declaredSizes;
  final bool omitSizes;
  final List<String> reads = [];
  bool failReads = false;

  @override
  Future<List<TransferEntry>> entries() async => [
    for (final entry in files.entries)
      TransferEntry(
        path: entry.key,
        kind: TransferEntryKind.regularFile,
        size: omitSizes ? null : declaredSizes[entry.key] ?? entry.value.length,
      ),
    for (final path in directories) TransferEntry(path: path, kind: TransferEntryKind.directory),
  ];

  @override
  Future<Uint8List> read(String path) async {
    reads.add(path);
    if (failReads) throw StateError('source read failed');
    return files[path]!;
  }
}
