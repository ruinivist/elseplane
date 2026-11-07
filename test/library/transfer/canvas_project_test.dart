// Verifies portable canvas project archive encoding and validation.
// Exercises document and attachment transfer at the project boundary.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../canvas/test_helpers.dart';

// ---------- Tests ----------

void main() {
  test('mixed projects round-trip with deterministic attachments', () async {
    final document =
        _document(
          markdown: '''
![first](attachments/00000000-0000-4000-8000-000000000000.png)
![second](attachments/00000001-0000-4000-8000-000000000000.png)
''',
        ).withElements(
          (elements) => elements
            ..add(_media(_path(2)))
            ..add(
              MediaElementData(
                id: 'link-media',
                position: const Offset(40, 50),
                width: 480,
                url: 'https://example.com/articles/design?tracking=kept',
              ),
            ),
        );
    final first = onePixelPngBytes;
    final second = Uint8List.fromList(onePixelPngBytes);
    final third = Uint8List.fromList(onePixelPngBytes);
    final store = TestAttachmentStore({
      _path(0): first,
      _path(1): second,
      _path(2): third,
    });

    final encoded = await encodeCanvasProject(document, store);
    final archive = ZipDecoder().decodeBytes(encoded);
    expect(archive.map((entry) => entry.name), ['document.json', _path(0), _path(1), _path(2)]);
    expect(
      utf8.decode(archive.find('document.json')!.readBytes()!),
      const JsonEncoder.withIndent('  ').convert(document.toJson()),
    );
    expect(archive.find(_path(0))!.readBytes(), first);
    expect(archive.find(_path(1))!.readBytes(), second);
    expect(archive.find(_path(2))!.readBytes(), third);

    final project = await decodeCanvasProject(encoded);
    expect(project.document.toJson(), document.toJson());
    expect(project.attachments[_path(0)], first);
    expect(project.attachments[_path(1)], second);
    expect(project.attachments[_path(2)], third);
  });

  test('local image discovery uses the Markdown AST', () {
    final document = _document(
      markdown: '''
attachments/00000000-0000-4000-8000-000000000000.png

```markdown
![fenced](attachments/00000001-0000-4000-8000-000000000000.png)
```

![local](attachments/00000000-0000-4000-8000-000000000000.png)
![duplicate](attachments/00000000-0000-4000-8000-000000000000.png)
![external](https://example.com/image.png)
![invalid](attachments/not-a-uuid.png)
![broken](attachments/00000001-0000-4000-8000-000000000000.png
''',
    ).withElements((elements) => elements.add(_media(_path(1))));
    final paths = canvasAttachmentPaths(document);

    expect(paths, {_path(0), _path(1)});
  });

  for (final (opening, closing) in [
    (r'$', r'$'),
    (r'\(', r'\)'),
    (r'$$', r'$$'),
    (r'\[', r'\]'),
    ('\$\$\n', '\n\$\$'),
    ('\\[\n', '\n\\]'),
  ]) {
    test('attachment transfers preserve literal math between $opening and $closing', () async {
      final path = _path(0);
      final contents = opening.contains('\n')
          ? '![literal](<$path>)\n\n[math]: $path\n\n![math]'
          : '![literal](<$path>) [math]: $path';
      final math = '$opening$contents$closing';
      final source = '$math\n\n![math]';
      final document = _document(markdown: source);

      expect(canvasAttachmentPaths(document), isEmpty);
      final literalProject = await decodeCanvasProject(await encodeCanvasProject(document, TestAttachmentStore()));
      expect(literalProject.attachments, isEmpty);
      expect(literalProject.document.toJson(), document.toJson());
      expect(
        rebaseCanvasDocumentAttachments(document, {path: _path(1)}).toJson(),
        document.toJson(),
      );

      String withImage(String destination) => '$source\n\n![real](<$destination>)';
      final mixed = _document(markdown: withImage(path));
      expect(canvasAttachmentPaths(mixed), {path});
      final project = await decodeCanvasProject(
        await encodeCanvasProject(mixed, TestAttachmentStore({path: onePixelPngBytes})),
      );
      final rebased = rebaseCanvasDocumentAttachments(project.document, {path: _path(1)});
      expect(rebased.elements.whereType<TextElementData>().single.markdown, withImage(_path(1)));
      expect(canvasAttachmentPaths(rebased), {_path(1)});
    });
  }

  for (final (opening, closing) in [
    (r'\$', r'\$'),
    (r'\\(', r'\\)'),
    (r'\\[', r'\\]'),
    (r'$', ''),
    (r'\(', ''),
    (r'$$', ''),
    (r'\[', ''),
    ('\$\$\n', ''),
    ('\\[\n', ''),
  ]) {
    test('images remain discoverable with literal delimiters $opening and $closing', () {
      String source(String path) => '$opening![real]($path)$closing';
      final document = _document(markdown: source(_path(0)));
      expect(canvasAttachmentPaths(document), {_path(0)});
      final rebased = rebaseCanvasDocumentAttachments(document, {_path(0): _path(1)});
      expect(rebased.elements.whereType<TextElementData>().single.markdown, source(_path(1)));
    });
  }

  test('repeated references are read and encoded once', () async {
    final document = _document(
      markdown: '![one](${_path(0)})\n![two](${_path(0)})',
    );
    final store = _CountingAttachmentStore({_path(0): onePixelPngBytes});

    await encodeCanvasProject(document, store);

    expect(store.reads, 1);
  });

  test('rebasing replaces matching markdown and media references without mutating the source', () {
    final document = _document(markdown: '![image](${_path(0)})')
        .withElements((elements) => elements.add(_media(_path(0))));
    final rebased = rebaseCanvasDocumentAttachments(document, {_path(0): _path(1)});
    expect(canvasAttachmentPaths(rebased), {_path(1)});
    expect(canvasAttachmentPaths(document), {_path(0)});
    expect(rebased.background, document.background);
    expect(rebased.elements.map((element) => element.id), document.elements.map((element) => element.id));
  });

  test('missing stored attachments fail export', () async {
    await expectLater(
      encodeCanvasProject(
        _document(markdown: '![missing](${_path(0)})'),
        TestAttachmentStore(),
      ),
      throwsStateError,
    );
  });

  test('rebasing changes image destinations while preserving matching source elsewhere', () {
    final path = _path(0);
    String markdown(String destination) =>
        '''
Prose $path

![alt $path](<$destination> "title $path")
[ordinary]($path)
`![inline]($path)`

```markdown
![fenced]($path)
```

    ![indented]($path)

\\!\\[escaped\\]($path)
![malformed]($path
''';
    final document = _document(markdown: markdown(path));
    final rebased = rebaseCanvasDocumentAttachments(document, {path: _path(1)});

    expect(rebased.elements.whereType<TextElementData>().single.markdown, markdown(_path(1)));
    expect(document.elements.whereType<TextElementData>().single.markdown, markdown(path));
  });

  test('rebasing deduplicates shared reference definitions and preserves unused definitions', () {
    String markdown(String destination) =>
        '''
![full][shared] ![shared][] ![shared] [ordinary][SHARED]

[shared]: <$destination> "title ${_path(0)}"
[shared]: ${_path(0)} "ignored duplicate"
[unused]: ${_path(0)}
''';
    final rebased = rebaseCanvasDocumentAttachments(_document(markdown: markdown(_path(0))), {_path(0): _path(1)});

    expect(rebased.elements.whereType<TextElementData>().single.markdown, markdown(_path(1)));
    expect(canvasAttachmentPaths(rebased), {_path(1)});
  });

  test('rebasing uses original GFM offsets across Unicode and CRLF', () {
    String markdown(String destination) =>
        '😀\r\n\r\n'
        '> - [x] ![nested](<$destination> "title")\r\n\r\n'
        '| Image |\r\n| --- |\r\n| ![table]($destination) |\r\n\r\n'
        'Note[^n]\r\n\r\n[^n]: ![footnote]($destination)\r\n';
    final destination = _path(1).replaceFirst('.png', '.webp');
    final document = _document(markdown: markdown(_path(0)));
    final rebased = rebaseCanvasDocumentAttachments(document, {_path(0): destination});

    expect(canvasAttachmentPaths(document), {_path(0)});
    expect(rebased.elements.whereType<TextElementData>().single.markdown, markdown(destination));
    expect(canvasAttachmentPaths(rebased), {destination});
  });

  test('rebasing sorts inline and shared reference destinations by source position', () {
    String markdown(String inline, String shared) =>
        '''
![first][shared] ![inline]($inline) ![shared][] ![shared]

[shared]: <$shared> "title ${_path(0)}"

Suffix ${_path(1)}
''';
    final inline = _path(2).replaceFirst('.png', '.jpg');
    final shared = _path(1).replaceFirst('.png', '.webp');
    final document = _document(markdown: markdown(_path(1), _path(0)));
    final rebased = rebaseCanvasDocumentAttachments(document, {
      _path(0): shared,
      _path(1): inline,
    });

    expect(rebased.elements.whereType<TextElementData>().single.markdown, markdown(inline, shared));
    expect(document.elements.whereType<TextElementData>().single.markdown, markdown(_path(1), _path(0)));
  });

  test('rebasing handles 16000 repeated images while preserving surrounding text', () {
    String markdown(String destination) =>
        'Prefix 😀\r\n\r\n'
        '${List.filled(16000, '![repeat](<$destination> "title")\r\n').join()}'
        '\r\nSuffix ${_path(0)}';
    final source = markdown(_path(0));
    final destination = _path(1).replaceFirst('.png', '.webp');
    final document = _document(markdown: source);
    final rebased = rebaseCanvasDocumentAttachments(document, {_path(0): destination});

    expect(rebased.elements.whereType<TextElementData>().single.markdown, markdown(destination));
    expect(document.elements.whereType<TextElementData>().single.markdown, source);
  });

  test('rebasing matches normalized destinations without cascading replacements', () {
    final escaped = _path(0).replaceFirst('/', r'\/');
    final source = '![one]($escaped) ![two](${_path(1)}) ![repeat](${_path(0)})';
    final rebased = rebaseCanvasDocumentAttachments(_document(markdown: source), {
      _path(0): _path(1),
      _path(1): _path(2),
    });

    expect(
      rebased.elements.whereType<TextElementData>().single.markdown,
      '![one](${_path(1)}) ![two](${_path(2)}) ![repeat](${_path(1)})',
    );
  });

  test('rejects malformed ZIPs, unsafe paths, duplicate entries, and symlinks', () async {
    await expectLater(decodeCanvasProject(Uint8List.fromList([1, 2, 3])), throwsFormatException);

    final unexpectedPath = _projectArchive(_document(markdown: ''))..add(ArchiveFile.bytes('../outside', Uint8List(0)));
    await expectLater(decodeCanvasProject(_encode(unexpectedPath)), throwsFormatException);

    final valid = _encode(_projectArchive(_document(markdown: '')));
    await expectLater(decodeCanvasProject(_duplicateFirstCentralEntry(valid)), throwsFormatException);
    await expectLater(decodeCanvasProject(_markFirstEntryAsSymlink(valid)), throwsFormatException);
  });

  test('rejects invalid documents, checksums, and attachment sets', () async {
    await expectLater(
      decodeCanvasProject(_encode(_projectArchive(_document(markdown: ''), documentJson: '{}'))),
      throwsFormatException,
    );
    await expectLater(
      decodeCanvasProject(_encode(_projectArchive(_document(markdown: ''), documentJson: 'not JSON'))),
      throwsFormatException,
    );
    await expectLater(
      decodeCanvasProject(_corruptFirstEntryChecksum(_encode(_projectArchive(_document(markdown: ''))))),
      throwsFormatException,
    );

    final missing = _document(markdown: '![missing](${_path(0)})');
    await expectLater(decodeCanvasProject(_encode(_projectArchive(missing))), throwsFormatException);

    final unreferenced = _projectArchive(_document(markdown: ''))..add(ArchiveFile.bytes(_path(0), onePixelPngBytes));
    await expectLater(decodeCanvasProject(_encode(unreferenced)), throwsFormatException);

    final corruptImage = _projectArchive(
      _document(markdown: '![corrupt](${_path(0)})'),
      attachments: {
        _path(0): Uint8List.fromList([1, 2, 3]),
      },
    );
    await expectLater(
      decodeCanvasProject(_encode(corruptImage)),
      throwsA(isA<FormatException>().having((error) => error.message, 'message', contains('Invalid encoded image'))),
    );
  });

  test('deflate output limits stop inflation before the compressed entry ends', () {
    final source = Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, 0x41);
    final archive = Archive()..add(ArchiveFile.bytes('payload', source)..compression = CompressionType.deflate);
    final encoded = _encode(archive);
    final header = (ZipDirectory()..read(InputMemoryStream(encoded))).fileHeaders.single;
    final input = header.file!.getStream(decompress: false);
    final output = _LimitedOutput(32);

    expect(() => Inflate.stream(input, output: output), throwsFormatException);
    expect(output.length, allOf(greaterThan(0), lessThanOrEqualTo(32)));
    expect(input.isEOS, isFalse);
  });

  test('attachment and project size limits reject only overages', () async {
    expect(
      () => validateCanvasProjectSize(canvasProjectMaximumBytes),
      returnsNormally,
    );
    expect(
      () => validateCanvasProjectSize(canvasProjectMaximumBytes + 1),
      throwsFormatException,
    );

    expect(
      () => validateAttachmentSize(attachmentMaximumBytes, 'over limit'),
      returnsNormally,
    );
    expect(
      () => validateAttachmentSize(attachmentMaximumBytes + 1, 'over limit'),
      throwsFormatException,
    );

    final document = _document(markdown: '![image](${_path(0)})');
    final overLimit = TestAttachmentStore({
      _path(0): Uint8List(attachmentMaximumBytes + 1),
    });
    await expectLater(
      encodeCanvasProject(document, overLimit),
      throwsFormatException,
    );

    final oversizedDocument = _encode(_projectArchive(_document(markdown: '')));
    await expectLater(
      decodeCanvasProject(_setFirstEntryDeclaredSize(oversizedDocument, canvasProjectMaximumBytes + 1)),
      throwsFormatException,
    );

    final oversizedAttachment = _encode(
      _projectArchive(
        _document(markdown: '![large](${_path(0)})'),
        attachments: {_path(0): Uint8List.fromList(onePixelPngBytes)},
      ),
    );
    await expectLater(
      decodeCanvasProject(_setEntryDeclaredSize(oversizedAttachment, _path(0), attachmentMaximumBytes + 1)),
      throwsFormatException,
    );

    final underdeclared = _encode(
      _projectArchive(_document(markdown: ''), documentJson: jsonEncode({'padding': List.filled(100000, 'x')})),
    );
    await expectLater(
      decodeCanvasProject(_corruptFirstEntryChecksum(_setFirstEntryDeclaredSize(underdeclared, 0))),
      throwsFormatException,
    );
  });

  test('project decoding validates incoming media sources before returning', () async {
    for (final source in [
      'javascript:alert(1)',
      'https://user:secret@example.com/path',
      'https://example.com/${List.filled(2049, 'x').join()}',
    ]) {
      final document = CanvasDocument(
        background: CanvasBackgroundKind.plain,
        elements: [_mediaSource('unsafe', source)],
      );
      await expectLater(decodeCanvasProject(_encode(_projectArchive(document))), throwsFormatException, reason: source);
    }

    final attachment = _path(3);
    final sources = [
      '',
      attachment,
      'https://example.com/image.JPEG?download=1',
      'https://example.com/article',
    ];
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [for (var index = 0; index < sources.length; index++) _mediaSource('media-$index', sources[index])],
    );
    final project = await decodeCanvasProject(
      _encode(_projectArchive(document, attachments: {attachment: onePixelPngBytes})),
    );
    expect(project.document.elements.whereType<MediaElementData>().map((element) => element.url), sources);
    expect(project.attachments[attachment], onePixelPngBytes);
  });
}

class _CountingAttachmentStore extends TestAttachmentStore {
  _CountingAttachmentStore([super.initial]);

  int reads = 0;

  @override
  Future<Uint8List> read(String path) async {
    reads++;
    return await super.read(path);
  }
}

class _LimitedOutput extends OutputMemoryStream {
  _LimitedOutput(this.maximumBytes) : super(size: maximumBytes);

  final int maximumBytes;

  void _check(int additionalBytes) {
    if (additionalBytes > maximumBytes - length) {
      throw const FormatException('Output limit exceeded');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}

// ---------- Test helpers ----------

Archive _projectArchive(
  CanvasDocument document, {
  String? documentJson,
  Map<String, Uint8List> attachments = const {},
}) {
  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'document.json',
        documentJson ?? const JsonEncoder.withIndent('  ').convert(document.toJson()),
      ),
    );
  for (final entry in attachments.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return archive;
}

Uint8List _encode(Archive archive) => ZipEncoder().encodeBytes(archive);

int _eocdOffset(Uint8List bytes) {
  for (var offset = bytes.length - 22; offset >= 0; offset--) {
    if (_readUint32(bytes, offset) == 0x06054b50) return offset;
  }
  throw StateError('No ZIP end record');
}

int _readUint16(Uint8List bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8);

int _readUint32(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);

void _writeUint16(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}

void _writeUint32(Uint8List bytes, int offset, int value) {
  for (var byte = 0; byte < 4; byte++) {
    bytes[offset + byte] = (value >> (8 * byte)) & 0xff;
  }
}

Uint8List _duplicateFirstCentralEntry(Uint8List source) {
  final eocd = _eocdOffset(source);
  final central = _readUint32(source, eocd + 16);
  final recordLength =
      46 + _readUint16(source, central + 28) + _readUint16(source, central + 30) + _readUint16(source, central + 32);
  final result = Uint8List(source.length + recordLength)
    ..setRange(0, eocd, source)
    ..setRange(eocd, eocd + recordLength, source, central)
    ..setRange(eocd + recordLength, source.length + recordLength, source, eocd);
  final updatedEocd = eocd + recordLength;
  _writeUint16(result, updatedEocd + 8, _readUint16(source, eocd + 8) + 1);
  _writeUint16(result, updatedEocd + 10, _readUint16(source, eocd + 10) + 1);
  _writeUint32(result, updatedEocd + 12, _readUint32(source, eocd + 12) + recordLength);
  return result;
}

Uint8List _markFirstEntryAsSymlink(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final central = _readUint32(bytes, _eocdOffset(bytes) + 16);
  _writeUint16(bytes, central + 4, (3 << 8) | 20);
  _writeUint32(bytes, central + 38, 0xa1ff0000);
  return bytes;
}

Uint8List _corruptFirstEntryChecksum(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final central = _readUint32(bytes, _eocdOffset(bytes) + 16);
  final local = _readUint32(bytes, central + 42);
  _writeUint32(bytes, central + 16, 0);
  _writeUint32(bytes, local + 14, 0);
  return bytes;
}

Uint8List _setFirstEntryDeclaredSize(Uint8List source, int size) {
  final bytes = Uint8List.fromList(source);
  final central = _readUint32(bytes, _eocdOffset(bytes) + 16);
  return _setEntryDeclaredSize(bytes, _readZipName(bytes, central), size);
}

Uint8List _setEntryDeclaredSize(Uint8List source, String name, int size) {
  final bytes = Uint8List.fromList(source);
  final eocd = _eocdOffset(bytes);
  var central = _readUint32(bytes, eocd + 16);
  final entries = _readUint16(bytes, eocd + 10);
  for (var index = 0; index < entries; index++) {
    final recordLength =
        46 + _readUint16(bytes, central + 28) + _readUint16(bytes, central + 30) + _readUint16(bytes, central + 32);
    if (_readZipName(bytes, central) == name) {
      _writeUint32(bytes, central + 24, size);
      _writeUint32(bytes, _readUint32(bytes, central + 42) + 22, size);
      return bytes;
    }
    central += recordLength;
  }
  throw StateError('No ZIP entry $name');
}

String _readZipName(Uint8List bytes, int centralHeader) {
  final length = _readUint16(bytes, centralHeader + 28);
  return utf8.decode(bytes.sublist(centralHeader + 46, centralHeader + 46 + length));
}

CanvasDocument _document({required String markdown}) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    TextElementData(
      id: 'text-1',
      position: const Offset(10, 20),
      width: 280,
      height: null,
      markdown: markdown,
      style: const TextNodeStyle(
        fontFamily: 'ABeeZee',
        color: Color(0xff201C1A),
      ),
    ),
    CodeElementData(
      id: 'code-1',
      position: const Offset(40, 50),
      size: const Size(280, 240),
      language: CodeLanguage.dart,
      source: 'void main() {}',
      title: 'main.dart',
      showLineNumbers: true,
    ),
    PenElementData(
      id: 'pen-1',
      position: Offset.zero,
      size: const Size(10, 10),
      hitSlop: 0,
      color: const Color(0xff000000),
      width: 1,
      points: const [PenPointData(Offset.zero, pressure: 0)],
    ),
    ArrowElementData(
      id: 'arrow-1',
      start: Offset.zero,
      controls: const [Offset(2, 2)],
      end: const Offset(4, 0),
      color: const Color(0xff000000),
      strokeStyle: ArrowStrokeStyle.solid,
      strokeWidth: 2,
    ),
  ],
);

MediaElementData _media(String url) => MediaElementData(
  id: 'media-1',
  position: const Offset(20, 30),
  width: 400,
  url: url,
);

MediaElementData _mediaSource(String id, String url) => MediaElementData(
  id: id,
  position: Offset.zero,
  width: 400,
  url: url,
);

String _path(int index) => 'attachments/0000000$index-0000-4000-8000-000000000000.png';
