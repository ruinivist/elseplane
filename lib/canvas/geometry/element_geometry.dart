// Calculates saved element translation and bounds from supplied layout measurements.
// Used by editor movement and clipboard placement without constructing views.

import 'dart:math' as math;
import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/geometry/arrow_geometry.dart';

// ---------- Transforms ----------

CanvasElementData moveElement(CanvasElementData value, Offset delta) => switch (value) {
  final TextElementData a => a.copyWith(position: a.position + delta),
  final CodeElementData a => a.copyWith(position: a.position + delta),
  final MediaElementData a => a.copyWith(position: a.position + delta),
  final ShapeElementData a => a.copyWith(position: a.position + delta),
  final PenElementData a => a.copyWith(position: a.position + delta),
  final ArrowElementData a => a.copyWith(
    start: a.start + delta,
    controls: [for (final point in a.controls) point + delta],
    end: a.end + delta,
  ),
};

Rect elementBounds(CanvasElementData value, {required double codeTitleHeight, required Size mediaSize}) =>
    switch (value) {
      final TextElementData a => a.position & Size(a.width, a.height ?? textNodeMinimumHeight),
      final CodeElementData a =>
        (a.position +
                Offset(
                  math.sin(a.rotation) * codeTitleHeight / 2,
                  -codeTitleHeight / 2 - math.cos(a.rotation) * codeTitleHeight / 2,
                )) &
            Size(a.size.width, a.size.height + codeTitleHeight),
      final MediaElementData a => a.position & mediaSize,
      final ShapeElementData a => a.position & a.size,
      final PenElementData a => a.position & a.size,
      final ArrowElementData a => ArrowGeometry(start: a.start, controls: a.controls, end: a.end).bounds,
    };

// ---------- Resizing and arrow editing ----------

TextElementData resizeTextElement(TextElementData value, Size renderedSize, Offset delta) => value.copyWith(
  width: math.max(textNodeMinimumWidth, value.width + delta.dx),
  height: math.max(textNodeMinimumHeight, (value.height ?? renderedSize.height) + delta.dy),
);

CodeElementData resizeCodeElement(CodeElementData value, Size size) => value.copyWith(
  size: Size(math.max(codeBlockMinimumSize.width, size.width), math.max(codeBlockMinimumSize.height, size.height)),
);

MediaElementData resizeMediaElement(MediaElementData value, Offset delta, double aspectRatio) {
  final inverseRatio = 1 / aspectRatio;
  final widthDelta = (delta.dx + delta.dy * inverseRatio) / (1 + inverseRatio * inverseRatio);
  return value.copyWith(width: math.max(mediaNodeMinimumWidth, value.width + widthDelta));
}

ShapeElementData resizeShapeElement(ShapeElementData value, Offset delta) => value.copyWith(
  size: Size(
    math.max(shapeMinimumSize.width, value.size.width + delta.dx),
    math.max(shapeMinimumSize.height, value.size.height + delta.dy),
  ),
);

ArrowElementData moveArrowPoint(ArrowElementData value, int index, Offset position) {
  RangeError.checkValueInInterval(index, 0, value.controls.length + 1, 'index');
  if (index == 0) return value.copyWith(start: minimumLengthArrowPoint(position, value.end, value.start));
  if (index == value.controls.length + 1) {
    return value.copyWith(end: minimumLengthArrowPoint(position, value.start, value.end));
  }
  return value.copyWith(controls: List.of(value.controls)..[index - 1] = position);
}
