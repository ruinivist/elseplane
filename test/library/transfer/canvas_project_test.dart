// Verifies portable canvas project archive encoding and validation.
// Exercises document and attachment transfer at the project boundary.

import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../canvas/test_helpers.dart';

// ---------- Tests ----------

void main() {
  test('mixed projects round-trip with deterministic attachments', () async {
    final document = _document(
      markdown: '''
![first](attachments/00000000-0000-4000-8000-000000000000.png)
![second](attachments/00000001-0000-4000-8000-000000000000.png)
''',
    ).withElements((elements) => elements.add(_media(_path(2))));
    final first = onePixelPngBytes;
    final second = Uint8List.fromList(onePixelPngBytes);
    final third = Uint8List.fromList(onePixelPngBytes);
    final store = TestAttachmentStore({
      _path(0): first,
      _path(1): second,
      _path(2): third,
    });

    final encoded = await encodeCanvasProject(document, store);
    final root = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    final attachmentMap = root['attachments'] as Map<String, dynamic>;
    expect(attachmentMap.keys, [_path(0), _path(1), _path(2)]);

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

  test('root, format, and document validation is strict', () async {
    final unknownRootKey = _validProjectJson()..['extra'] = true;
    await expectLater(_decodeJson(unknownRootKey), throwsFormatException);

    final wrongFormat = _validProjectJson()..['format'] = 'other';
    await expectLater(_decodeJson(wrongFormat), throwsFormatException);

    final wrongVersion = _validProjectJson()
      ..['document'] = {
        'version': 1,
        'background': 'dotGrid',
        'elements': <Object?>[],
      };
    await expectLater(_decodeJson(wrongVersion), throwsFormatException);
  });

  test('invalid paths, base64, image data, and attachment sets fail', () async {
    final invalidPath = _validProjectJson()..['attachments'] = {'attachments/not-a-uuid.png': 'AAAA'};
    await expectLater(_decodeJson(invalidPath), throwsFormatException);

    final invalidBase64 = _validProjectJson()..['attachments'] = {_path(0): 'not base64'};
    await expectLater(_decodeJson(invalidBase64), throwsFormatException);

    final malformedImage = _validProjectJson()
      ..['attachments'] = {
        _path(0): base64Encode(<int>[1, 2, 3]),
      };
    await expectLater(_decodeJson(malformedImage), throwsFormatException);

    final missingAttachment = _validProjectJson()
      ..['document'] = _document(markdown: '![missing](${_path(0)})').toJson();
    await expectLater(_decodeJson(missingAttachment), throwsFormatException);

    final extraAttachment = _validProjectJson()..['attachments'] = {_path(0): base64Encode(onePixelPngBytes)};
    await expectLater(_decodeJson(extraAttachment), throwsFormatException);
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

    final document = _document(markdown: '![image](${_path(0)})');
    final atLimit = TestAttachmentStore({
      _path(0): Uint8List(attachmentMaximumBytes),
    });
    await encodeCanvasProject(document, atLimit);

    final overLimit = TestAttachmentStore({
      _path(0): Uint8List(attachmentMaximumBytes + 1),
    });
    await expectLater(
      encodeCanvasProject(document, overLimit),
      throwsFormatException,
    );
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

// ---------- Test helpers ----------

Future<CanvasProject> _decodeJson(Map<String, Object?> value) =>
    decodeCanvasProject(Uint8List.fromList(utf8.encode(jsonEncode(value))));

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

Map<String, Object?> _validProjectJson() => {
  'format': 'elseplane-canvas',
  'document': _document(markdown: '').toJson(),
  'attachments': <String, Object?>{},
};

String _path(int index) => 'attachments/0000000$index-0000-4000-8000-000000000000.png';
