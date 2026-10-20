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
