// Defines the persisted canvas document schema, element data, and validation.
// Used by the editor, storage, clipboard, and project import/export flows.

// Immutable values stay independent of Flutter metadata.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'dart:ui';

import 'package:json_annotation/json_annotation.dart';

part 'canvas_document.g.dart';
part 'canvas_element.dart';
part 'document_codec.dart';

// ---------- Constants ----------

const textNodeMinimumWidth = 160.0;
const textNodeMinimumHeight = 52.0;

const codeBlockMinimumSize = Size(280, 240);
const mediaNodeMinimumWidth = 120.0;
const arrowMinimumLength = 4.0;
const arrowStrokeWidthMinimum = 1.0;
const arrowStrokeWidthMaximum = 5.75;
const shapeMinimumSize = Size.square(32);
const penStreamlineMinimum = 0.0;
const penStreamlineMaximum = 1.0;
const penStreamlineDefault = 0.5;

// ---------- Document value ----------

/// Holds the background and ordered elements of a persisted canvas.
/// Used as the shared document value across editing, storage, and transfer.
@_strictJson
final class CanvasDocument {
  // ---------- Construction ----------

  CanvasDocument({required this.background, required List<CanvasElementData> elements})
    : schemaVersion = version,
      elements = List.unmodifiable(elements);

  CanvasDocument._json({
    required this.schemaVersion,
    required this.background,
    required List<CanvasElementData> elements,
  }) : elements = List.unmodifiable(elements);

  factory CanvasDocument.fromJson(Object? json) {
    final document = _decode(json, 'document', _$CanvasDocumentFromJson);
    if (document.schemaVersion != version) {
      throw const FormatException('document.version must be $version');
    }
    final ids = <String>{};
    for (final element in document.elements) {
      if (!ids.add(element.id)) {
        throw FormatException('Duplicate canvas element id: ${element.id}');
      }
    }
    return document;
  }

  // ---------- Constants ----------

  static const version = 8;

  // ---------- State ----------

  @JsonKey(name: 'version', fromJson: _jsonInt)
  final int schemaVersion;
  final CanvasBackgroundKind background;
  final List<CanvasElementData> elements;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasDocument && background == other.background && _valuesEqual(elements, other.elements);

  @override
  int get hashCode => Object.hash(background, Object.hashAll(elements));

  // ---------- Serialization ----------

  Map<String, Object?> toJson() => _$CanvasDocumentToJson(this);

  // ---------- Copying ----------

  CanvasDocument copyWith({CanvasBackgroundKind? background, List<CanvasElementData>? elements}) => CanvasDocument(
    background: background ?? this.background,
    elements: elements ?? this.elements,
  );
}
