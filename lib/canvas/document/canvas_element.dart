// Defines immutable saved element values and document enums.
// Shared by editing, storage, clipboard, and project transfer.

part of 'canvas_document.dart';

// ---------- Types ----------

/// Identifies the geometry rendered by a shape element.
/// Used by shape tools, models, and document serialization.
enum ShapeKind {
  rectangle,
  roundedRectangle,
  ellipse,
  diamond,
  triangle,
  hexagon,
}

/// Identifies how an arrow shaft is rendered.
/// Used by arrow tools, models, and document serialization.
enum ArrowStrokeStyle { solid, dashed }

/// Identifies the background treatment of text and code blocks.
/// Used by block settings, rendering, and document serialization.
enum BlockBackgroundKind { transparent, card, glass }

enum CanvasBackgroundKind { dotGrid, plain }

enum CodeLanguage {
  python,
  typescript,
  javascript,
  java,
  csharp,
  cpp,
  c,
  go,
  rust,
  sql,
  bash,
  kotlin,
  swift,
  php,
  ruby,
  dart,
  html,
  css,
  json,
  yaml,
  markdown,
  plainText,
}

/// Defines the shared identity and serialization contract for canvas elements.
/// Used by document parsing and every concrete editor element model.
sealed class CanvasElementData {
  // ---------- Construction ----------

  const CanvasElementData(this.id, this.type, {this.autoArrange = true});

  factory CanvasElementData.fromJson(Object? json) {
    final value = _jsonMap(json, 'element');
    return switch (value['type']) {
      'text' => TextElementData.fromJson(value),
      'code' => CodeElementData.fromJson(value),
      'media' => MediaElementData.fromJson(value),
      'shape' => ShapeElementData.fromJson(value),
      'pen' => PenElementData.fromJson(value),
      'arrow' => ArrowElementData.fromJson(value),
      final type when type is String => throw FormatException(
        'Unknown canvas element type: $type',
      ),
      _ => throw const FormatException('element.type must be a string'),
    };
  }

  // ---------- State ----------

  final String id;
  final String type;
  @JsonKey(defaultValue: true)
  final bool autoArrange;

  // ---------- Interface ----------

  Map<String, Object?> toJson();

  CanvasElementData copyWith({String? id, bool? autoArrange});

  // ---------- Validation ----------

  void validateType(String expected) {
    if (id.isEmpty) throw const FormatException('element.id must not be empty');
    if (type != expected) {
      throw FormatException('element.type must be $expected');
    }
  }
}

/// Stores the editable geometry and appearance of a shape element.
/// Used by the shape tool and its canvas model.
@_strictJson
final class ShapeElementData extends CanvasElementData {
  // ---------- Construction ----------

  ShapeElementData({
    required String id,
    required this.kind,
    required this.position,
    required this.size,
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
    super.autoArrange,
  }) : super(id, 'shape');

  ShapeElementData._json({
    required String id,
    required String type,
    required this.kind,
    required this.position,
    required this.size,
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
    super.autoArrange,
  }) : super(id, type);

  factory ShapeElementData.fromJson(Object? json) {
    final shape = _decode(json, 'shape element', _$ShapeElementDataFromJson)..validateType('shape');
    if (shape.size.width < shapeMinimumSize.width || shape.size.height < shapeMinimumSize.height) {
      throw const FormatException('element.size is below the shape minimum');
    }
    _validatePositive(shape.strokeWidth, 'element.strokeWidth');
    return shape;
  }

  // ---------- State ----------

  final ShapeKind kind;
  @_OffsetConverter()
  final Offset position;
  @_SizeConverter()
  final Size size;
  @_ArgbColorConverter()
  final Color strokeColor;
  @JsonKey(fromJson: _nullableArgbFromJson, toJson: _nullableArgbToJson)
  final Color? fillColor;
  final double strokeWidth;

  // ---------- Serialization ----------

  @override
  Map<String, Object?> toJson() => _$ShapeElementDataToJson(this);

  // ---------- Copying ----------

  @override
  ShapeElementData copyWith({
    String? id,
    bool? autoArrange,
    ShapeKind? kind,
    Offset? position,
    Size? size,
    Color? strokeColor,
    Color? fillColor,
    bool clearFillColor = false,
    double? strokeWidth,
  }) => ShapeElementData(
    autoArrange: autoArrange ?? this.autoArrange,
    id: id ?? this.id,
    kind: kind ?? this.kind,
    position: position ?? this.position,
    size: size ?? this.size,
    strokeColor: strokeColor ?? this.strokeColor,
    fillColor: clearFillColor ? null : fillColor ?? this.fillColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
  );
}

/// Stores the position, width, rotation, and source URL of a media element.
/// Used by media nodes and document attachment handling.
@_strictJson
final class MediaElementData extends CanvasElementData {
  // ---------- Construction ----------

  MediaElementData({
    required String id,
    required this.position,
    required this.width,
    required this.url,
    super.autoArrange,
    this.rotation = 0,
  }) : super(id, 'media');

  MediaElementData._json({
    required String id,
    required String type,
    required this.position,
    required this.width,
    required this.url,
    required this.rotation,
    super.autoArrange,
  }) : super(id, type);

  factory MediaElementData.fromJson(Object? json) {
    final media = _decode(json, 'media element', _$MediaElementDataFromJson)..validateType('media');
    _validateFinite(media.width, 'element.width');
    if (media.width < mediaNodeMinimumWidth) {
      throw const FormatException('element.width is below the minimum');
    }
    _validateFinite(media.rotation, 'element.rotation');
    return media;
  }

  // ---------- State ----------

  @_OffsetConverter()
  final Offset position;
  final double width;
  final String url;
  @JsonKey(defaultValue: 0.0)
  final double rotation;

  // ---------- Serialization ----------

  @override
  Map<String, Object?> toJson() => _$MediaElementDataToJson(this);

  // ---------- Copying ----------

  @override
  MediaElementData copyWith({
    String? id,
    bool? autoArrange,
    Offset? position,
    double? width,
    String? url,
    double? rotation,
  }) => MediaElementData(
    autoArrange: autoArrange ?? this.autoArrange,
    id: id ?? this.id,
    position: position ?? this.position,
    width: width ?? this.width,
    url: url ?? this.url,
    rotation: rotation ?? this.rotation,
  );
}

/// Stores the font, color, and background settings applied to a text element.
/// Used by text element data and the text editor model.
@_strictJson
final class TextNodeStyle {
  // ---------- Construction ----------

  const TextNodeStyle({
    required this.fontFamily,
    this.color,
    this.background = BlockBackgroundKind.card,
  });

  const TextNodeStyle._json({
    required this.fontFamily,
    required this.color,
    required this.background,
  });

  factory TextNodeStyle.fromJson(Object? json) {
    final style = _decode(json, 'style', _$TextNodeStyleFromJson);
    if (style.fontFamily.trim().isEmpty) {
      throw const FormatException('style.fontFamily must not be blank');
    }
    return style;
  }

  // ---------- State ----------

  final String fontFamily;

  /// Null uses the theme's heading and body colors.
  @_TextColorConverter()
  final Color? color;
  final BlockBackgroundKind background;

  // ---------- Copying ----------

  TextNodeStyle copyWith({
    String? fontFamily,
    Color? color,
    bool clearColor = false,
    BlockBackgroundKind? background,
  }) {
    return TextNodeStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      color: clearColor ? null : color ?? this.color,
      background: background ?? this.background,
    );
  }

  // ---------- Serialization ----------

  Map<String, Object?> toJson() => _$TextNodeStyleToJson(this);
}

/// Stores editable text content, layout, rotation, and styling.
/// Used by text blocks and document serialization.
@_strictJson
final class TextElementData extends CanvasElementData {
  // ---------- Construction ----------

  TextElementData({
    required String id,
    required this.position,
    required double width,
    required double? height,
    required this.markdown,
    required this.style,
    super.autoArrange,
    this.rotation = 0,
  }) : textSize = (width: width, height: height),
       super(id, 'text');

  TextElementData._json({
    required String id,
    required String type,
    required this.position,
    required this.textSize,
    required this.markdown,
    required this.style,
    required this.rotation,
    super.autoArrange,
  }) : super(id, type);

  factory TextElementData.fromJson(Object? json) {
    final text = _decode(json, 'text element', _$TextElementDataFromJson)..validateType('text');
    if (text.width < textNodeMinimumWidth) {
      throw const FormatException('element.size.width is below the minimum');
    }
    if (text.height != null && text.height! < textNodeMinimumHeight) {
      throw const FormatException('element.size.height is below the minimum');
    }
    _validateFinite(text.rotation, 'element.rotation');
    return text;
  }

  // ---------- State ----------

  @_OffsetConverter()
  final Offset position;
  @JsonKey(name: 'size', fromJson: _textSizeFromJson, toJson: _textSizeToJson)
  final ({double width, double? height}) textSize;
  final String markdown;
  final TextNodeStyle style;
  final double rotation;

  @JsonKey(includeFromJson: false, includeToJson: false)
  double get width => textSize.width;

  @JsonKey(includeFromJson: false, includeToJson: false)
  double? get height => textSize.height;

  // ---------- Serialization ----------

  @override
  Map<String, Object?> toJson() => _$TextElementDataToJson(this);

  // ---------- Copying ----------

  @override
  TextElementData copyWith({
    String? id,
    bool? autoArrange,
    Offset? position,
    double? width,
    double? height,
    bool clearHeight = false,
    String? markdown,
    TextNodeStyle? style,
    double? rotation,
  }) => TextElementData(
    autoArrange: autoArrange ?? this.autoArrange,
    id: id ?? this.id,
    position: position ?? this.position,
    width: width ?? this.width,
    height: clearHeight ? null : height ?? this.height,
    markdown: markdown ?? this.markdown,
    style: style ?? this.style,
    rotation: rotation ?? this.rotation,
  );
}

/// Stores code content, presentation settings, position, size, and rotation.
/// Used by code block models and document serialization.
@_strictJson
final class CodeElementData extends CanvasElementData {
  // ---------- Construction ----------

  CodeElementData({
    required String id,
    required this.position,
    required this.size,
    required this.language,
    required this.source,
    required this.title,
    required this.showLineNumbers,
    super.autoArrange,
    this.background = BlockBackgroundKind.card,
    this.rotation = 0,
  }) : super(id, 'code');

  CodeElementData._json({
    required String id,
    required String type,
    required this.position,
    required this.size,
    required this.language,
    required this.source,
    required this.title,
    required this.showLineNumbers,
    required this.background,
    required this.rotation,
    super.autoArrange,
  }) : super(id, type);

  factory CodeElementData.fromJson(Object? json) {
    final code = _decode(json, 'code element', _$CodeElementDataFromJson)..validateType('code');
    if (code.size.width < codeBlockMinimumSize.width || code.size.height < codeBlockMinimumSize.height) {
      throw const FormatException('element.size is below the minimum');
    }
    _validateFinite(code.rotation, 'element.rotation');
    return code;
  }

  // ---------- State ----------

  @_OffsetConverter()
  final Offset position;
  @_SizeConverter()
  final Size size;
  final CodeLanguage language;
  final String source;
  final String title;
  final bool showLineNumbers;
  @JsonKey(defaultValue: BlockBackgroundKind.card)
  final BlockBackgroundKind background;
  @JsonKey(defaultValue: 0.0)
  final double rotation;

  // ---------- Serialization ----------

  @override
  Map<String, Object?> toJson() => _$CodeElementDataToJson(this);

  // ---------- Copying ----------

  @override
  CodeElementData copyWith({
    String? id,
    bool? autoArrange,
    Offset? position,
    Size? size,
    CodeLanguage? language,
    String? source,
    String? title,
    bool? showLineNumbers,
    BlockBackgroundKind? background,
    double? rotation,
  }) => CodeElementData(
    autoArrange: autoArrange ?? this.autoArrange,
    id: id ?? this.id,
    position: position ?? this.position,
    size: size ?? this.size,
    language: language ?? this.language,
    source: source ?? this.source,
    title: title ?? this.title,
    showLineNumbers: showLineNumbers ?? this.showLineNumbers,
    background: background ?? this.background,
    rotation: rotation ?? this.rotation,
  );
}

/// Stores a sampled pen position and its input pressure.
/// Used by pen strokes during rendering and serialization.
@_strictJson
final class PenPointData {
  // ---------- Construction ----------

  const PenPointData(this.position, {required this.pressure});

  PenPointData._json({
    required double x,
    required double y,
    required this.pressure,
  }) : position = Offset(x, y);

  factory PenPointData.fromJson(Object? json) {
    final point = _decode(json, 'pen point', _$PenPointDataFromJson);
    _validateFinite(point.x, 'point.x');
    _validateFinite(point.y, 'point.y');
    _validateFinite(point.pressure, 'point.pressure');
    if (point.pressure < 0 || point.pressure > 1) {
      throw const FormatException('point.pressure must be between 0 and 1');
    }
    return point;
  }

  // ---------- State ----------

  @JsonKey(includeFromJson: false, includeToJson: false)
  final Offset position;
  final double pressure;

  double get x => position.dx;
  double get y => position.dy;

  // ---------- Serialization ----------

  Map<String, Object?> toJson() => _$PenPointDataToJson(this);
}

/// Stores the sampled path and appearance of a freehand pen stroke.
/// Used by pen stroke models and document serialization.
@_strictJson
final class PenElementData extends CanvasElementData {
  // ---------- Construction ----------

  PenElementData({
    required String id,
    required this.position,
    required this.size,
    required this.hitSlop,
    required List<PenPointData> points,
    required this.color,
    required this.width,
    super.autoArrange,
    this.streamline = penStreamlineDefault,
  }) : points = List.unmodifiable(points),
       super(id, 'pen');

  PenElementData._json({
    required String id,
    required String type,
    required this.position,
    required this.size,
    required this.hitSlop,
    required List<PenPointData> points,
    required this.color,
    required this.width,
    required this.streamline,
    super.autoArrange,
  }) : points = List.unmodifiable(points),
       super(id, type);

  PenElementData._copy(
    PenElementData original, {
    String? id,
    bool? autoArrange,
    Offset? position,
    Size? size,
    double? hitSlop,
    List<PenPointData>? points,
    Color? color,
    double? width,
    double? streamline,
  }) : position = position ?? original.position,
       size = size ?? original.size,
       hitSlop = hitSlop ?? original.hitSlop,
       points = points == null ? original.points : List.unmodifiable(points),
       color = color ?? original.color,
       width = width ?? original.width,
       streamline = streamline ?? original.streamline,
       super(id ?? original.id, original.type, autoArrange: autoArrange ?? original.autoArrange);

  factory PenElementData.fromJson(Object? json) {
    final pen = _decode(json, 'pen element', _$PenElementDataFromJson)..validateType('pen');
    _validateFinite(pen.hitSlop, 'element.hitSlop');
    if (pen.hitSlop < 0) {
      throw const FormatException('element.hitSlop must be non-negative');
    }
    if (pen.points.isEmpty) {
      throw const FormatException('element.points must not be empty');
    }
    _validatePositive(pen.width, 'element.width');
    _validateFinite(pen.streamline, 'element.streamline');
    if (pen.streamline < penStreamlineMinimum || pen.streamline > penStreamlineMaximum) {
      throw const FormatException('element.streamline is outside the supported range');
    }
    return pen;
  }

  // ---------- State ----------

  @_OffsetConverter()
  final Offset position;
  @_SizeConverter()
  final Size size;
  final double hitSlop;
  final List<PenPointData> points;
  @_ArgbColorConverter()
  final Color color;
  final double width;
  final double streamline;

  // ---------- Serialization ----------

  @override
  Map<String, Object?> toJson() => _$PenElementDataToJson(this);

  // ---------- Copying ----------

  @override
  PenElementData copyWith({
    String? id,
    bool? autoArrange,
    Offset? position,
    Size? size,
    double? hitSlop,
    List<PenPointData>? points,
    Color? color,
    double? width,
    double? streamline,
  }) => PenElementData._copy(
    this,
    id: id,
    autoArrange: autoArrange,
    position: position,
    size: size,
    hitSlop: hitSlop,
    points: points,
    color: color,
    width: width,
    streamline: streamline,
  );
}

/// Stores the control points that define a curved arrow.
/// Used by arrow models and document serialization.
@_strictJson
final class ArrowElementData extends CanvasElementData {
  // ---------- Construction ----------

  ArrowElementData({
    required String id,
    required this.start,
    required List<Offset> controls,
    required this.end,
    required this.color,
    required this.strokeStyle,
    required this.strokeWidth,
    super.autoArrange,
  }) : controls = List.unmodifiable(controls),
       super(id, 'arrow');

  ArrowElementData._json({
    required String id,
    required String type,
    required this.start,
    required List<Offset> controls,
    required this.end,
    required this.color,
    required this.strokeStyle,
    required this.strokeWidth,
    super.autoArrange,
  }) : controls = List.unmodifiable(controls),
       super(id, type);

  ArrowElementData._copy(
    ArrowElementData original, {
    String? id,
    bool? autoArrange,
    Offset? start,
    List<Offset>? controls,
    Offset? end,
    Color? color,
    ArrowStrokeStyle? strokeStyle,
    double? strokeWidth,
  }) : start = start ?? original.start,
       controls = controls == null ? original.controls : List.unmodifiable(controls),
       end = end ?? original.end,
       color = color ?? original.color,
       strokeStyle = strokeStyle ?? original.strokeStyle,
       strokeWidth = strokeWidth ?? original.strokeWidth,
       super(id ?? original.id, original.type, autoArrange: autoArrange ?? original.autoArrange);

  factory ArrowElementData.fromJson(Object? json) {
    final arrow = _decode(json, 'arrow element', _$ArrowElementDataFromJson)..validateType('arrow');
    if (arrow.controls.isEmpty) {
      throw const FormatException('element.controls must not be empty');
    }
    if ((arrow.end - arrow.start).distance < arrowMinimumLength) {
      throw const FormatException('element arrow is shorter than the minimum');
    }
    _validateFinite(arrow.strokeWidth, 'element.strokeWidth');
    if (arrow.strokeWidth < arrowStrokeWidthMinimum || arrow.strokeWidth > arrowStrokeWidthMaximum) {
      throw const FormatException('element.strokeWidth is outside the supported range');
    }
    return arrow;
  }

  // ---------- State ----------

  @_OffsetConverter()
  final Offset start;
  @_OffsetConverter()
  final List<Offset> controls;
  @_OffsetConverter()
  final Offset end;
  @_ArgbColorConverter()
  final Color color;
  final ArrowStrokeStyle strokeStyle;
  final double strokeWidth;

  // ---------- Serialization ----------

  @override
  Map<String, Object?> toJson() => _$ArrowElementDataToJson(this);

  // ---------- Copying ----------

  @override
  ArrowElementData copyWith({
    String? id,
    bool? autoArrange,
    Offset? start,
    List<Offset>? controls,
    Offset? end,
    Color? color,
    ArrowStrokeStyle? strokeStyle,
    double? strokeWidth,
  }) => ArrowElementData._copy(
    this,
    id: id,
    autoArrange: autoArrange,
    start: start,
    controls: controls,
    end: end,
    color: color,
    strokeStyle: strokeStyle,
    strokeWidth: strokeWidth,
  );
}
