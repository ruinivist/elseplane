// Builds paths for the saved canvas shape kinds.
// Shared by shape previews, persisted rendering, and hit testing.

import 'dart:math' as math;
import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';

// ---------- Geometry ----------

/// Builds a closed path for a shape kind inside the supplied bounds.
/// Used by preview and persisted-shape painters.
Path shapePath(ShapeKind kind, Rect rect) => switch (kind) {
  ShapeKind.rectangle => Path()..addRect(rect),
  ShapeKind.roundedRectangle =>
    Path()..addRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.min(16, rect.shortestSide / 2)),
      ),
    ),
  ShapeKind.ellipse => Path()..addOval(rect),
  ShapeKind.diamond =>
    Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.center.dy)
      ..lineTo(rect.center.dx, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..close(),
  ShapeKind.triangle =>
    Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close(),
  ShapeKind.hexagon =>
    Path()
      ..moveTo(rect.left + rect.width * 0.25, rect.top)
      ..lineTo(rect.left + rect.width * 0.75, rect.top)
      ..lineTo(rect.right, rect.center.dy)
      ..lineTo(rect.left + rect.width * 0.75, rect.bottom)
      ..lineTo(rect.left + rect.width * 0.25, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..close(),
};

/// Returns a conservative text rectangle centered inside a shape's bounds.
/// Used by shape text preview and editing layout.
Rect shapeTextBounds(ShapeKind kind, Size size, double strokeWidth) {
  final baseSize = switch (kind) {
    ShapeKind.rectangle || ShapeKind.roundedRectangle => Size(
      math.max(0, size.width - 16),
      math.max(0, size.height - 16),
    ),
    ShapeKind.ellipse => Size(
      size.width / math.sqrt2,
      size.height / math.sqrt2,
    ),
    ShapeKind.diamond => Size(size.width * 0.5, size.height * 0.5),
    ShapeKind.triangle => Size(size.width * 0.25, size.height * 0.5),
    ShapeKind.hexagon => Size(size.width * 0.5, size.height),
  };
  final inset = strokeWidth / 2;
  final width = math.max<double>(0, baseSize.width - inset * 2);
  final height = math.max<double>(0, baseSize.height - inset * 2);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: width,
    height: height,
  );
}
