// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'canvas_document.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CanvasDocument _$CanvasDocumentFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CanvasDocument', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const ['version', 'background', 'elements'],
      );
      final val = CanvasDocument._json(
        schemaVersion: $checkedConvert('version', (v) => _jsonInt(v)),
        background: $checkedConvert(
          'background',
          (v) => $enumDecode(_$CanvasBackgroundKindEnumMap, v),
        ),
        elements: $checkedConvert(
          'elements',
          (v) => (v as List<dynamic>).map(CanvasElementData.fromJson).toList(),
        ),
      );
      return val;
    }, fieldKeyMap: const {'schemaVersion': 'version'});

Map<String, dynamic> _$CanvasDocumentToJson(CanvasDocument instance) =>
    <String, dynamic>{
      'version': instance.schemaVersion,
      'background': _$CanvasBackgroundKindEnumMap[instance.background]!,
      'elements': instance.elements.map((e) => e.toJson()).toList(),
    };

const _$CanvasBackgroundKindEnumMap = {
  CanvasBackgroundKind.dotGrid: 'dotGrid',
  CanvasBackgroundKind.plain: 'plain',
};

ShapeElementData _$ShapeElementDataFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ShapeElementData', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'id',
      'type',
      'autoArrange',
      'kind',
      'position',
      'size',
      'strokeColor',
      'fillColor',
      'strokeWidth',
    ],
  );
  final val = ShapeElementData._json(
    id: $checkedConvert('id', (v) => v as String),
    type: $checkedConvert('type', (v) => v as String),
    kind: $checkedConvert('kind', (v) => $enumDecode(_$ShapeKindEnumMap, v)),
    position: $checkedConvert(
      'position',
      (v) => const _OffsetConverter().fromJson(v as Map<String, dynamic>),
    ),
    size: $checkedConvert(
      'size',
      (v) => const _SizeConverter().fromJson(v as Map<String, dynamic>),
    ),
    strokeColor: $checkedConvert(
      'strokeColor',
      (v) => const _ArgbColorConverter().fromJson(v),
    ),
    fillColor: $checkedConvert('fillColor', (v) => _nullableArgbFromJson(v)),
    strokeWidth: $checkedConvert('strokeWidth', (v) => (v as num).toDouble()),
    autoArrange: $checkedConvert('autoArrange', (v) => v as bool? ?? true),
  );
  return val;
});

Map<String, dynamic> _$ShapeElementDataToJson(ShapeElementData instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'autoArrange': instance.autoArrange,
      'kind': _$ShapeKindEnumMap[instance.kind]!,
      'position': const _OffsetConverter().toJson(instance.position),
      'size': const _SizeConverter().toJson(instance.size),
      'strokeColor': ?const _ArgbColorConverter().toJson(instance.strokeColor),
      'fillColor': ?_nullableArgbToJson(instance.fillColor),
      'strokeWidth': instance.strokeWidth,
    };

const _$ShapeKindEnumMap = {
  ShapeKind.rectangle: 'rectangle',
  ShapeKind.roundedRectangle: 'roundedRectangle',
  ShapeKind.ellipse: 'ellipse',
  ShapeKind.diamond: 'diamond',
  ShapeKind.triangle: 'triangle',
  ShapeKind.hexagon: 'hexagon',
};

MediaElementData _$MediaElementDataFromJson(Map<String, dynamic> json) =>
    $checkedCreate('MediaElementData', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const [
          'id',
          'type',
          'autoArrange',
          'position',
          'width',
          'url',
          'rotation',
        ],
      );
      final val = MediaElementData._json(
        id: $checkedConvert('id', (v) => v as String),
        type: $checkedConvert('type', (v) => v as String),
        position: $checkedConvert(
          'position',
          (v) => const _OffsetConverter().fromJson(v as Map<String, dynamic>),
        ),
        width: $checkedConvert('width', (v) => (v as num).toDouble()),
        url: $checkedConvert('url', (v) => v as String),
        rotation: $checkedConvert(
          'rotation',
          (v) => (v as num?)?.toDouble() ?? 0.0,
        ),
        autoArrange: $checkedConvert('autoArrange', (v) => v as bool? ?? true),
      );
      return val;
    });

Map<String, dynamic> _$MediaElementDataToJson(MediaElementData instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'autoArrange': instance.autoArrange,
      'position': const _OffsetConverter().toJson(instance.position),
      'width': instance.width,
      'url': instance.url,
      'rotation': instance.rotation,
    };

TextNodeStyle _$TextNodeStyleFromJson(Map<String, dynamic> json) =>
    $checkedCreate('TextNodeStyle', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const ['fontFamily', 'color', 'background'],
      );
      final val = TextNodeStyle._json(
        fontFamily: $checkedConvert('fontFamily', (v) => v as String),
        color: $checkedConvert(
          'color',
          (v) => _$JsonConverterFromJson<String, Color>(
            v,
            const _TextColorConverter().fromJson,
          ),
        ),
        background: $checkedConvert(
          'background',
          (v) => $enumDecode(_$BlockBackgroundKindEnumMap, v),
        ),
      );
      return val;
    });

Map<String, dynamic> _$TextNodeStyleToJson(TextNodeStyle instance) =>
    <String, dynamic>{
      'fontFamily': instance.fontFamily,
      'color': ?_$JsonConverterToJson<String, Color>(
        instance.color,
        const _TextColorConverter().toJson,
      ),
      'background': _$BlockBackgroundKindEnumMap[instance.background]!,
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) => json == null ? null : fromJson(json as Json);

const _$BlockBackgroundKindEnumMap = {
  BlockBackgroundKind.transparent: 'transparent',
  BlockBackgroundKind.card: 'card',
  BlockBackgroundKind.glass: 'glass',
};

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) => value == null ? null : toJson(value);

TextElementData _$TextElementDataFromJson(Map<String, dynamic> json) =>
    $checkedCreate('TextElementData', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const [
          'id',
          'type',
          'autoArrange',
          'position',
          'size',
          'markdown',
          'style',
          'rotation',
        ],
      );
      final val = TextElementData._json(
        id: $checkedConvert('id', (v) => v as String),
        type: $checkedConvert('type', (v) => v as String),
        position: $checkedConvert(
          'position',
          (v) => const _OffsetConverter().fromJson(v as Map<String, dynamic>),
        ),
        textSize: $checkedConvert(
          'size',
          (v) => _textSizeFromJson(v as Map<String, dynamic>),
        ),
        markdown: $checkedConvert('markdown', (v) => v as String),
        style: $checkedConvert('style', (v) => TextNodeStyle.fromJson(v)),
        rotation: $checkedConvert('rotation', (v) => (v as num).toDouble()),
        autoArrange: $checkedConvert('autoArrange', (v) => v as bool? ?? true),
      );
      return val;
    }, fieldKeyMap: const {'textSize': 'size'});

Map<String, dynamic> _$TextElementDataToJson(TextElementData instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'autoArrange': instance.autoArrange,
      'position': const _OffsetConverter().toJson(instance.position),
      'size': _textSizeToJson(instance.textSize),
      'markdown': instance.markdown,
      'style': instance.style.toJson(),
      'rotation': instance.rotation,
    };

CodeElementData _$CodeElementDataFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CodeElementData', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const [
          'id',
          'type',
          'autoArrange',
          'position',
          'size',
          'language',
          'source',
          'title',
          'showLineNumbers',
          'background',
          'rotation',
        ],
      );
      final val = CodeElementData._json(
        id: $checkedConvert('id', (v) => v as String),
        type: $checkedConvert('type', (v) => v as String),
        position: $checkedConvert(
          'position',
          (v) => const _OffsetConverter().fromJson(v as Map<String, dynamic>),
        ),
        size: $checkedConvert(
          'size',
          (v) => const _SizeConverter().fromJson(v as Map<String, dynamic>),
        ),
        language: $checkedConvert(
          'language',
          (v) => $enumDecode(_$CodeLanguageEnumMap, v),
        ),
        source: $checkedConvert('source', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        showLineNumbers: $checkedConvert('showLineNumbers', (v) => v as bool),
        background: $checkedConvert(
          'background',
          (v) =>
              $enumDecodeNullable(_$BlockBackgroundKindEnumMap, v) ??
              BlockBackgroundKind.card,
        ),
        rotation: $checkedConvert(
          'rotation',
          (v) => (v as num?)?.toDouble() ?? 0.0,
        ),
        autoArrange: $checkedConvert('autoArrange', (v) => v as bool? ?? true),
      );
      return val;
    });

Map<String, dynamic> _$CodeElementDataToJson(CodeElementData instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'autoArrange': instance.autoArrange,
      'position': const _OffsetConverter().toJson(instance.position),
      'size': const _SizeConverter().toJson(instance.size),
      'language': _$CodeLanguageEnumMap[instance.language]!,
      'source': instance.source,
      'title': instance.title,
      'showLineNumbers': instance.showLineNumbers,
      'background': _$BlockBackgroundKindEnumMap[instance.background]!,
      'rotation': instance.rotation,
    };

const _$CodeLanguageEnumMap = {
  CodeLanguage.python: 'python',
  CodeLanguage.typescript: 'typescript',
  CodeLanguage.javascript: 'javascript',
  CodeLanguage.java: 'java',
  CodeLanguage.csharp: 'csharp',
  CodeLanguage.cpp: 'cpp',
  CodeLanguage.c: 'c',
  CodeLanguage.go: 'go',
  CodeLanguage.rust: 'rust',
  CodeLanguage.sql: 'sql',
  CodeLanguage.bash: 'bash',
  CodeLanguage.kotlin: 'kotlin',
  CodeLanguage.swift: 'swift',
  CodeLanguage.php: 'php',
  CodeLanguage.ruby: 'ruby',
  CodeLanguage.dart: 'dart',
  CodeLanguage.html: 'html',
  CodeLanguage.css: 'css',
  CodeLanguage.json: 'json',
  CodeLanguage.yaml: 'yaml',
  CodeLanguage.markdown: 'markdown',
  CodeLanguage.plainText: 'plainText',
};

PenPointData _$PenPointDataFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PenPointData', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['pressure', 'x', 'y']);
      final val = PenPointData._json(
        x: $checkedConvert('x', (v) => (v as num).toDouble()),
        y: $checkedConvert('y', (v) => (v as num).toDouble()),
        pressure: $checkedConvert('pressure', (v) => (v as num).toDouble()),
      );
      return val;
    });

Map<String, dynamic> _$PenPointDataToJson(PenPointData instance) =>
    <String, dynamic>{
      'pressure': instance.pressure,
      'x': instance.x,
      'y': instance.y,
    };

PenElementData _$PenElementDataFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PenElementData', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const [
          'id',
          'type',
          'autoArrange',
          'position',
          'size',
          'hitSlop',
          'points',
          'color',
          'width',
          'streamline',
        ],
      );
      final val = PenElementData._json(
        id: $checkedConvert('id', (v) => v as String),
        type: $checkedConvert('type', (v) => v as String),
        position: $checkedConvert(
          'position',
          (v) => const _OffsetConverter().fromJson(v as Map<String, dynamic>),
        ),
        size: $checkedConvert(
          'size',
          (v) => const _SizeConverter().fromJson(v as Map<String, dynamic>),
        ),
        hitSlop: $checkedConvert('hitSlop', (v) => (v as num).toDouble()),
        points: $checkedConvert(
          'points',
          (v) => (v as List<dynamic>).map(PenPointData.fromJson).toList(),
        ),
        color: $checkedConvert(
          'color',
          (v) => const _ArgbColorConverter().fromJson(v),
        ),
        width: $checkedConvert('width', (v) => (v as num).toDouble()),
        streamline: $checkedConvert('streamline', (v) => (v as num).toDouble()),
        autoArrange: $checkedConvert('autoArrange', (v) => v as bool? ?? true),
      );
      return val;
    });

Map<String, dynamic> _$PenElementDataToJson(PenElementData instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'autoArrange': instance.autoArrange,
      'position': const _OffsetConverter().toJson(instance.position),
      'size': const _SizeConverter().toJson(instance.size),
      'hitSlop': instance.hitSlop,
      'points': instance.points.map((e) => e.toJson()).toList(),
      'color': ?const _ArgbColorConverter().toJson(instance.color),
      'width': instance.width,
      'streamline': instance.streamline,
    };

ArrowElementData _$ArrowElementDataFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ArrowElementData', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'id',
      'type',
      'autoArrange',
      'start',
      'controls',
      'end',
      'color',
      'strokeStyle',
      'strokeWidth',
    ],
  );
  final val = ArrowElementData._json(
    id: $checkedConvert('id', (v) => v as String),
    type: $checkedConvert('type', (v) => v as String),
    start: $checkedConvert(
      'start',
      (v) => const _OffsetConverter().fromJson(v as Map<String, dynamic>),
    ),
    controls: $checkedConvert(
      'controls',
      (v) => (v as List<dynamic>)
          .map(
            (e) => const _OffsetConverter().fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    ),
    end: $checkedConvert(
      'end',
      (v) => const _OffsetConverter().fromJson(v as Map<String, dynamic>),
    ),
    color: $checkedConvert(
      'color',
      (v) => const _ArgbColorConverter().fromJson(v),
    ),
    strokeStyle: $checkedConvert(
      'strokeStyle',
      (v) => $enumDecode(_$ArrowStrokeStyleEnumMap, v),
    ),
    strokeWidth: $checkedConvert('strokeWidth', (v) => (v as num).toDouble()),
    autoArrange: $checkedConvert('autoArrange', (v) => v as bool? ?? true),
  );
  return val;
});

Map<String, dynamic> _$ArrowElementDataToJson(
  ArrowElementData instance,
) => <String, dynamic>{
  'id': instance.id,
  'type': instance.type,
  'autoArrange': instance.autoArrange,
  'start': const _OffsetConverter().toJson(instance.start),
  'controls': instance.controls.map(const _OffsetConverter().toJson).toList(),
  'end': const _OffsetConverter().toJson(instance.end),
  'color': ?const _ArgbColorConverter().toJson(instance.color),
  'strokeStyle': _$ArrowStrokeStyleEnumMap[instance.strokeStyle]!,
  'strokeWidth': instance.strokeWidth,
};

const _$ArrowStrokeStyleEnumMap = {
  ArrowStrokeStyle.solid: 'solid',
  ArrowStrokeStyle.dashed: 'dashed',
};
