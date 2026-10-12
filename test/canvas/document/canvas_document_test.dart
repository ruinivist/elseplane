// Verifies canvas document serialization and boundary validation.
// Exercises every persisted element model and malformed input path.

import 'dart:convert';
import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_background.dart';
import 'package:elseplane/canvas/tools/code/code_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  test('Auto defaults, copies, and strict serialization cover every element type', () {
    final fixtures = [
      _encodedText(),
      _encodedCode(),
      _encodedMedia(),
      _encodedPen(),
      _encodedArrow(),
      ShapeElementData(
        id: 'shape',
        kind: ShapeKind.rectangle,
        position: Offset.zero,
        size: const Size.square(80),
        strokeColor: 0xff000000,
        fillColor: null,
        strokeWidth: 2,
      ).toJson(),
    ];
    for (final fixture in fixtures) {
      final element = CanvasElementData.fromJson(fixture);
      expect(element.autoArrange, isTrue);
      element.autoArrange = false;
      expect(element.copy(id: 'copy').autoArrange, isFalse);
      expect(CanvasElementData.fromJson(element.toJson()).autoArrange, isFalse);
      expect(
        () => CanvasElementData.fromJson({...fixture, 'autoArrange': 'yes'}),
        throwsFormatException,
      );
    }
  });

  test('canvas documents round-trip mixed element data', () {
    const source = '## Authentication\n\n- [x] OAuth callback\n\n\$a^2 + b^2 = c^2\$';
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        ArrowElementData(
          id: 'arrow-1',
          start: const Offset(10, 20),
          controls: const [Offset(40, 5), Offset(60, 40)],
          end: const Offset(80, 60),
          color: 0xffdc3f3f,
          strokeStyle: ArrowStrokeStyle.dashed,
          strokeWidth: 3,
        ),
        TextElementData(
          id: 'text-1',
          position: const Offset(-120, 200),
          width: 320,
          height: 180,
          markdown: source,
          rotation: math.pi * 3,
          style: const TextNodeStyle(
            fontFamily: 'Inter',
            color: '#201C1A',
            background: BlockBackgroundKind.transparent,
          ),
        ),
        PenElementData(
          id: 'pen-1',
          position: const Offset(-40, 30),
          size: const Size(180, 90),
          hitSlop: 6,
          color: 0xff000000,
          width: 3,
          streamline: 0.75,
          points: const [
            PenPointData(Offset(6, 6), pressure: 0.4),
          ],
        ),
        CodeElementData(
          id: 'code-1',
          position: const Offset(100, 200),
          size: const Size(600, 400),
          language: CodeLanguage.dart,
          source: 'void main() {}',
          title: 'main.dart',
          showLineNumbers: true,
          rotation: math.pi / 2,
        ),
        MediaElementData(
          id: 'media-1',
          position: const Offset(220, -80),
          width: 400,
          url: 'https://example.com/image.png',
          rotation: math.pi / 4,
        ),
        ShapeElementData(
          id: 'shape-1',
          kind: ShapeKind.ellipse,
          position: const Offset(300, 120),
          size: const Size(180, 100),
          strokeColor: 0xff2f6fde,
          fillColor: 0xffffc936,
          strokeWidth: 3,
        ),
      ],
    );

    final encoded = jsonEncode(document.toJson());
    final restored = CanvasDocument.fromJson(jsonDecode(encoded));
    final elements = restored.elements;

    expect(restored.toJson()['version'], CanvasDocument.version);
    expect(restored.background, CanvasBackgroundKind.plain);
    expect(elements.map((element) => element.id), [
      'arrow-1',
      'text-1',
      'pen-1',
      'code-1',
      'media-1',
      'shape-1',
    ]);
    expect(elements[0], isA<ArrowElementData>());
    expect(elements[1], isA<TextElementData>());
    expect(elements[2], isA<PenElementData>());
    expect(elements[3], isA<CodeElementData>());
    expect(elements[4], isA<MediaElementData>());
    expect(elements[5], isA<ShapeElementData>());

    final node = elements[1] as TextElementData;
    expect(node.position, const Offset(-120, 200));
    expect(node.width, 320);
    expect(node.height, 180);
    expect(node.rotation, math.pi * 3);
    expect(node.markdown, source);
    expect(node.style.fontFamily, 'Inter');
    expect(node.style.color, '#201C1A');
    expect(node.style.background, BlockBackgroundKind.transparent);

    final pen = elements[2] as PenElementData;
    expect(pen.size, const Size(180, 90));
    expect(pen.streamline, 0.75);
    expect(pen.hitSlop, 6);
    expect(pen.points.single.pressure, 0.4);

    final code = elements[3] as CodeElementData;
    expect(code.position, const Offset(100, 200));
    expect(code.size, const Size(600, 400));
    expect(code.language, CodeLanguage.dart);
    expect(code.source, 'void main() {}');
    expect(code.title, 'main.dart');
    expect(code.showLineNumbers, isTrue);
    expect(code.rotation, math.pi / 2);

    final media = elements[4] as MediaElementData;
    expect(media.position, const Offset(220, -80));
    expect(media.width, 400);
    expect(media.url, 'https://example.com/image.png');
    expect(media.rotation, math.pi / 4);

    final shape = elements[5] as ShapeElementData;
    expect(shape.kind, ShapeKind.ellipse);
    expect(shape.position, const Offset(300, 120));
    expect(shape.size, const Size(180, 100));
    expect(shape.strokeColor, 0xff2f6fde);
    expect(shape.fillColor, 0xffffc936);
    expect(shape.strokeWidth, 3);

    final arrow = elements[0] as ArrowElementData;
    expect(arrow.start, const Offset(10, 20));
    expect(arrow.controls, const [Offset(40, 5), Offset(60, 40)]);
    expect(arrow.end, const Offset(80, 60));
    expect(arrow.color, 0xffdc3f3f);
    expect(arrow.strokeStyle, ArrowStrokeStyle.dashed);
    expect(arrow.strokeWidth, 3);

    final snapshot = document.copy();
    final copiedArrow = snapshot.elements.first as ArrowElementData;
    expect(copiedArrow.controls, isNot(same(arrow.controls)));
    copiedArrow.controls[0] = Offset.zero;
    expect(arrow.controls.first, const Offset(40, 5));
    expect(snapshot.elements, isNot(same(document.elements)));
    expect(
      (snapshot.elements[2] as PenElementData).points,
      isNot(same((document.elements[2] as PenElementData).points)),
    );
  });

  test('unknown document versions are rejected', () {
    expect(
      () => CanvasDocument.fromJson(_document(version: CanvasDocument.version - 1)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(_document()..['version'] = 2.5),
      throwsA(isA<FormatException>()),
    );
  });

  test('theme-default text colors round-trip, copy, and retain explicit overrides', () {
    const style = TextNodeStyle(fontFamily: 'Inter', background: BlockBackgroundKind.glass);
    expect(style.toJson(), isNot(contains('color')));
    for (final json in [style.toJson(), style.toJson()..['color'] = null]) {
      final restored = TextNodeStyle.fromJson(jsonDecode(jsonEncode(json)));
      expect(restored.color, isNull);
      expect(restored.fontFamily, style.fontFamily);
      expect(restored.background, style.background);
      expect(restored.copyWith().toJson(), style.toJson());
      expect(restored.copyWith(background: BlockBackgroundKind.transparent).color, isNull);
    }
    final custom = style.copyWith(color: '#ABCDEF');
    expect(TextNodeStyle.fromJson(custom.toJson()).color, custom.color);
    expect(custom.copyWith(background: BlockBackgroundKind.card).color, custom.color);
    expect(() => TextNodeStyle.fromJson(style.toJson()..['color'] = 123), throwsFormatException);
  });

  test('text backgrounds round-trip and reject invalid or legacy styles', () {
    const defaultStyle = TextNodeStyle(fontFamily: 'Inter', color: '#201C1A');
    expect(defaultStyle.background, BlockBackgroundKind.card);
    for (final background in BlockBackgroundKind.values) {
      final style = defaultStyle.copyWith(background: background);
      final restored = TextNodeStyle.fromJson(jsonDecode(jsonEncode(style.toJson())));
      expect(style.toJson()['background'], background.name);
      expect(restored.background, background);
      expect(restored.fontFamily, defaultStyle.fontFamily);
      expect(restored.color, defaultStyle.color);
    }
    for (final background in ['unsupported', null, true]) {
      expect(
        () => TextNodeStyle.fromJson(defaultStyle.toJson()..['background'] = background),
        throwsFormatException,
      );
    }
    expect(
      () => TextNodeStyle.fromJson(
        defaultStyle.toJson()
          ..remove('background')
          ..['noFill'] = false,
      ),
      throwsFormatException,
    );
  });

  test('code rotation defaults to zero when omitted', () {
    final code = _encodedCode()..remove('rotation');
    final restored =
        CanvasDocument.fromJson(
              _document(elements: [code]),
            ).elements.single
            as CodeElementData;

    expect(restored.rotation, 0);
  });

  test('code backgrounds default to card and survive serialization and copying', () {
    final code = CodeElementData.fromJson(_encodedCode());
    expect(code.background, BlockBackgroundKind.card);
    for (final background in BlockBackgroundKind.values) {
      code.background = background;
      final restored = CodeElementData.fromJson(jsonDecode(jsonEncode(code.toJson())));
      expect(restored.background, background);
      expect(code.copy(id: 'copy').background, background);
    }
    for (final invalid in ['unsupported', true, 1]) {
      expect(
        () => CodeElementData.fromJson(_encodedCode()..['background'] = invalid),
        throwsFormatException,
      );
    }
  });

  test('media rotation defaults to zero when omitted', () {
    final media = _encodedMedia()..remove('rotation');
    final restored =
        CanvasDocument.fromJson(
              _document(elements: [media]),
            ).elements.single
            as MediaElementData;

    expect(restored.rotation, 0);
  });

  test('shape kinds and minimum dimensions are validated', () {
    Map<String, Object?> shape({
      Object kind = 'diamond',
      double width = 32,
      Object strokeColor = 0xff000000,
      Object strokeWidth = 2.0,
    }) => {
      'id': 'shape',
      'type': 'shape',
      'kind': kind,
      'position': {'x': 0.0, 'y': 0.0},
      'size': {'width': width, 'height': 32.0},
      'strokeColor': strokeColor,
      'strokeWidth': strokeWidth,
    };

    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [shape(kind: 'star')]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [shape(width: 31)]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [shape(strokeColor: -1)]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [shape(strokeColor: 1.5)]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [shape(strokeWidth: 0)]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('unknown document keys are rejected', () {
    final document = _document()..['extra'] = true;

    expect(
      () => CanvasDocument.fromJson(document),
      throwsA(isA<FormatException>()),
    );
  });

  test('unknown element keys are rejected', () {
    final document = _document(elements: [_encodedText()..['extra'] = true]);

    expect(
      () => CanvasDocument.fromJson(document),
      throwsA(isA<FormatException>()),
    );
  });

  test('unknown position keys are rejected', () {
    final document = _document(
      elements: [
        _encodedText(position: {'x': 0.0, 'y': 0.0, 'extra': true}),
      ],
    );

    expect(
      () => CanvasDocument.fromJson(document),
      throwsA(isA<FormatException>()),
    );
  });

  test('unknown style keys are rejected', () {
    final document = _document(
      elements: [
        _encodedText(
          style: {
            'fontFamily': 'Source Serif 4',
            'color': '#201C1A',
            'extra': true,
          },
        ),
      ],
    );

    expect(
      () => CanvasDocument.fromJson(document),
      throwsA(isA<FormatException>()),
    );
  });

  test('duplicate IDs are rejected across element types', () {
    expect(
      () => CanvasDocument.fromJson(
        _document(
          elements: [
            _encodedText(id: 'same'),
            _encodedCode(id: 'same'),
          ],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('non-finite text values are rejected', () {
    expect(
      () => CanvasDocument.fromJson(
        _document(
          elements: [
            _encodedText(position: {'x': double.infinity, 'y': 0}),
          ],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [_encodedText(width: double.nan)]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [_encodedText(height: double.nan)]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [_encodedText(rotation: double.infinity)]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [_encodedCode(rotation: double.infinity)]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [_encodedMedia(rotation: double.infinity)]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('text dimensions and styles are validated', () {
    expect(
      () => CanvasDocument.fromJson(
        _document(
          elements: [_encodedText(width: textNodeMinimumWidth - 1)],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(
          elements: [_encodedText(height: textNodeMinimumHeight - 1)],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [_encodedText(fontFamily: 'Arial')]),
      ),
      throwsA(isA<FormatException>()),
    );

    for (final color in ['#201c1a', '#21A', '#80201C1A', '201C1A']) {
      expect(
        () => CanvasDocument.fromJson(
          _document(elements: [_encodedText(color: color)]),
        ),
        throwsA(isA<FormatException>()),
        reason: color,
      );
    }
  });

  test('missing text height keeps automatic sizing', () {
    final node = CanvasDocument.fromJson(_document()).elements.single as TextElementData;

    expect(node.height, isNull);
    expect(node.toJson()['size'], isNot(contains('height')));
  });

  test('malformed non-text elements are rejected', () {
    final code = _encodedCode();
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [code..['language'] = 'unknown']),
      ),
      throwsA(isA<FormatException>()),
    );

    final pen = _encodedPen();
    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [pen..['points'] = <Object?>[]]),
      ),
      throwsA(isA<FormatException>()),
    );
    for (final streamline in [-0.25, 1.25, double.nan]) {
      expect(
        () => CanvasDocument.fromJson(
          _document(elements: [_encodedPen()..['streamline'] = streamline]),
        ),
        throwsA(isA<FormatException>()),
      );
    }

    final arrow = _encodedArrow();
    expect(
      () => CanvasDocument.fromJson(
        _document(
          elements: [
            arrow..['end'] = {'x': 1.0, 'y': 1.0},
          ],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    for (final invalid in [
      _encodedArrow()..['controls'] = [],
      _encodedArrow()
        ..['controls'] = [
          {'x': double.nan, 'y': 0},
        ],
      _encodedArrow()
        ..['controls'] = [
          {'x': 1},
        ],
      _encodedArrow()..['controls'] = null,
      _encodedArrow()..['color'] = -1,
      _encodedArrow()..['strokeStyle'] = 'dotted',
      _encodedArrow()..['strokeWidth'] = 0.0,
      _encodedArrow()..['strokeWidth'] = 5.25,
    ]) {
      expect(
        () => CanvasDocument.fromJson(_document(elements: [invalid])),
        throwsA(isA<FormatException>()),
      );
    }

    expect(
      () => CanvasDocument.fromJson(
        _document(elements: [_encodedMedia(width: mediaNodeMinimumWidth - 1)]),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

// ---------- Fixtures ----------

Map<String, Object?> _document({
  int version = CanvasDocument.version,
  List<Map<String, Object?>>? elements,
}) {
  return {
    'version': version,
    'background': 'dotGrid',
    'elements': elements ?? [_encodedText()],
  };
}

Map<String, Object?> _encodedText({
  String id = 'text-1',
  Map<String, Object?> position = const {'x': 0.0, 'y': 0.0},
  Object width = textNodeDefaultWidth,
  Object? height,
  Object rotation = 0.0,
  String fontFamily = 'Source Serif 4',
  String color = '#201C1A',
  Map<String, Object?>? style,
}) {
  return {
    'id': id,
    'type': 'text',
    'position': position,
    'size': <String, Object?>{'width': width, 'height': ?height},
    'rotation': rotation,
    'markdown': '',
    'style':
        style ??
        {
          'fontFamily': fontFamily,
          'color': color,
          'background': 'card',
        },
  };
}

Map<String, Object?> _encodedCode({String id = 'code-1', Object rotation = 0.0}) => {
  'id': id,
  'type': 'code',
  'position': {'x': 0.0, 'y': 0.0},
  'size': {'width': 280.0, 'height': 240.0},
  'language': 'dart',
  'source': '',
  'title': '',
  'showLineNumbers': true,
  'rotation': rotation,
};

Map<String, Object?> _encodedMedia({Object width = mediaNodeDefaultWidth, Object rotation = 0.0}) => {
  'id': 'media',
  'type': 'media',
  'position': {'x': 0.0, 'y': 0.0},
  'width': width,
  'url': '',
  'rotation': rotation,
};

Map<String, Object?> _encodedPen({String id = 'pen-1'}) => {
  'id': id,
  'type': 'pen',
  'position': {'x': 0.0, 'y': 0.0},
  'size': {'width': 10.0, 'height': 10.0},
  'hitSlop': 0.0,
  'color': 0,
  'width': 1.0,
  'streamline': penStreamlineDefault,
  'points': [
    {'x': 0.0, 'y': 0.0, 'pressure': 0.0},
  ],
};

Map<String, Object?> _encodedArrow({String id = 'arrow-1'}) => {
  'id': id,
  'type': 'arrow',
  'start': {'x': 0.0, 'y': 0.0},
  'controls': [
    {'x': 2.0, 'y': 2.0},
  ],
  'end': {'x': 4.0, 'y': 0.0},
  'color': 0xff000000,
  'strokeStyle': 'solid',
  'strokeWidth': 2.0,
};
