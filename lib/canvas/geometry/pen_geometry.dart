// Defines raw pen strokes, smoothed paths, hit padding, and canvas positioning.
// Used by pen sampling, persisted stroke models, rendering, and hit testing.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/geometry/hit_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

// ---------- Types and geometry ----------

/// Carries sampled screen-space points with their committed pen options.
/// Produced by the pen tool and positioned by the canvas editor.
typedef RawPenStroke = ({
  List<PenPointData> points,
  Color color,
  double width,
  double streamline,
});

const _strokeHitSlop = 6.0;

/// Builds the filled freehand outline for sampled pen points.
/// Used by live previews and persisted stroke rendering.
Path createPenPath(List<PenPointData> points, double width, double streamline) {
  final simulatePressure = points.isNotEmpty && points.every((point) => point.pressure == points.first.pressure);
  final outline = pf.getStroke(
    [
      for (final point in points)
        pf.PointVector(
          point.position.dx,
          point.position.dy,
          point.pressure,
        ),
    ],
    options: pf.StrokeOptions(
      size: width * 2,
      streamline: streamline,
      simulatePressure: simulatePressure,
    ),
  );
  if (outline.isEmpty) return Path();
  if (outline.length == 1) {
    return Path()..addOval(Rect.fromCircle(center: outline.single, radius: 1));
  }
  final path = Path()..moveTo(outline.first.dx, outline.first.dy);
  for (var index = 1; index < outline.length - 1; index++) {
    final point = outline[index];
    final next = outline[index + 1];
    path.quadraticBezierTo(
      point.dx,
      point.dy,
      (point.dx + next.dx) / 2,
      (point.dy + next.dy) / 2,
    );
  }
  return path;
}

// ---------- Persistence geometry ----------

/// Converts a sampled screen-space stroke into persisted canvas coordinates.
/// Used when the canvas editor commits a completed [RawPenStroke].
PenElementData positionStroke(
  RawPenStroke stroke, {
  required String id,
  required Offset canvasOffset,
  required double canvasScale,
}) {
  final positions = stroke.points.map((point) => point.position);
  final minX = positions.map((point) => point.dx).reduce((a, b) => a < b ? a : b);
  final minY = positions.map((point) => point.dy).reduce((a, b) => a < b ? a : b);
  final maxX = positions.map((point) => point.dx).reduce((a, b) => a > b ? a : b);
  final maxY = positions.map((point) => point.dy).reduce((a, b) => a > b ? a : b);
  final padding = stroke.width + _strokeHitSlop;
  final screenOrigin = Offset(minX - padding, minY - padding);

  return PenElementData(
    id: id,
    position: screenOrigin / canvasScale + canvasOffset,
    hitSlop: _strokeHitSlop / canvasScale,
    size: Size(maxX - minX + padding * 2, maxY - minY + padding * 2) / canvasScale,
    points: [
      for (final point in stroke.points)
        PenPointData(
          (point.position - screenOrigin) / canvasScale,
          pressure: point.pressure,
        ),
    ],
    color: stroke.color,
    width: stroke.width / canvasScale,
    streamline: stroke.streamline,
  );
}

// ---------- Hit testing ----------

bool hitTestPenStroke(
  Offset position, {
  required List<PenPointData> points,
  required double width,
  required double hitSlop,
}) {
  final radiusSquared = (width + hitSlop) * (width + hitSlop);
  if (points.length == 1) {
    return (position - points.single.position).distanceSquared <= radiusSquared;
  }
  for (var index = 1; index < points.length; index++) {
    if (distanceToSegmentSquared(
          position,
          points[index - 1].position,
          points[index].position,
        ) <=
        radiusSquared) {
      return true;
    }
  }
  return false;
}
