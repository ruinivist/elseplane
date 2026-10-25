// Defines arrow paths, bounds, hit testing, and endpoint constraints.
// Used by arrow models, creation previews, rendering, and hit testing.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';

import 'package:elseplane/canvas/geometry/hit_test.dart';

// ---------- Geometry ----------

const _arrowHeadLength = 12.0;
const _arrowHeadHalfWidth = 5.0;
const _arrowHitSlop = 8.0;

/// Calculates the curve, arrowhead, and interaction bounds of an arrow.
/// Used by arrow models, painters, and previews.
class ArrowGeometry {
  ArrowGeometry({
    required this.start,
    required List<Offset> controls,
    required this.end,
  }) : assert(controls.isNotEmpty, 'An arrow needs at least one control'),
       controls = List.unmodifiable(controls);

  final Offset start;
  final List<Offset> controls;
  final Offset end;

  Offset get endTangent {
    for (final point in [...controls.reversed, start]) {
      final tangent = end - point;
      if (tangent != Offset.zero) return tangent / tangent.distance;
    }
    return const Offset(1, 0);
  }

  Offset get arrowheadBase => end - endTangent * _arrowHeadLength;

  Offset get arrowheadLeft {
    final tangent = endTangent;
    return arrowheadBase + Offset(-tangent.dy, tangent.dx) * _arrowHeadHalfWidth;
  }

  Offset get arrowheadRight {
    final tangent = endTangent;
    return arrowheadBase - Offset(-tangent.dy, tangent.dx) * _arrowHeadHalfWidth;
  }

  Path get shaftPath {
    final path = Path()..moveTo(start.dx, start.dy);
    for (var index = 0; index < controls.length; index++) {
      final control = controls[index];
      final join = index == controls.length - 1 ? end : (control + controls[index + 1]) / 2;
      path.quadraticBezierTo(control.dx, control.dy, join.dx, join.dy);
    }
    return path;
  }

  Path get arrowheadPath {
    return Path()
      ..moveTo(arrowheadLeft.dx, arrowheadLeft.dy)
      ..lineTo(end.dx, end.dy)
      ..lineTo(arrowheadRight.dx, arrowheadRight.dy);
  }

  Rect get bounds => shaftPath
      .getBounds()
      .expandToInclude(arrowheadPath.getBounds())
      .inflate(_arrowHitSlop + arrowStrokeWidthMaximum / 2);

  bool hitTest(Offset position, {required double strokeWidth}) {
    final radius = strokeWidth / 2 + _arrowHitSlop;
    final radiusSquared = radius * radius;
    for (final metric in shaftPath.computeMetrics()) {
      var previous = start;
      final steps = (metric.length / (radius / 2)).ceil();
      for (var index = 1; index <= steps; index++) {
        final current = metric.getTangentForOffset(metric.length * index / steps)!.position;
        if (distanceToSegmentSquared(position, previous, current) <= radiusSquared) {
          return true;
        }
        previous = current;
      }
    }
    return distanceToSegmentSquared(
              position,
              arrowheadLeft,
              end,
            ) <=
            radiusSquared ||
        distanceToSegmentSquared(
              position,
              end,
              arrowheadRight,
            ) <=
            radiusSquared;
  }

  ArrowGeometry shift(Offset offset) => ArrowGeometry(
    start: start + offset,
    controls: [for (final control in controls) control + offset],
    end: end + offset,
  );
}

Offset minimumLengthArrowPoint(Offset requested, Offset fixed, Offset current) {
  final vector = requested - fixed;
  if (vector.distance >= arrowMinimumLength) return requested;
  final fallback = current - fixed;
  final direction = vector == Offset.zero ? fallback / fallback.distance : vector / vector.distance;
  return fixed + direction * (arrowMinimumLength + 1e-6);
}

// ---------- Saved arrow access ----------

extension ArrowElementGeometry on ArrowElementData {
  ArrowGeometry get geometry => ArrowGeometry(start: start, controls: controls, end: end);
  Rect get bounds => geometry.bounds;
  ArrowGeometry get localGeometry => geometry.shift(-bounds.topLeft);
  int get pointCount => controls.length + 2;
  Offset point(int index) {
    RangeError.checkValidIndex(index, this, 'index', pointCount);
    return index == 0
        ? start
        : index == pointCount - 1
        ? end
        : controls[index - 1];
  }
}
