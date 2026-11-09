// Verifies conservative text bounds remain inside each saved shape path.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/geometry/shape_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text bounds are centered and all four corners lie inside each shape', () {
    const size = Size(240, 180);
    const strokeWidth = 4.0;
    for (final kind in ShapeKind.values) {
      final bounds = shapeTextBounds(kind, size, strokeWidth);
      expect(bounds.center.dx, closeTo(size.width / 2, 1e-9), reason: '$kind center x');
      expect(bounds.center.dy, closeTo(size.height / 2, 1e-9), reason: '$kind center y');
      expect(bounds.width, greaterThanOrEqualTo(0), reason: '$kind width');
      expect(bounds.height, greaterThanOrEqualTo(0), reason: '$kind height');
      expect(bounds.left.isFinite && bounds.top.isFinite, isTrue, reason: '$kind finite');

      final path = shapePath(kind, Offset.zero & size);
      for (final corner in [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomLeft,
        bounds.bottomRight,
      ]) {
        expect(path.contains(corner), isTrue, reason: '$kind corner $corner');
      }
    }
  });

  test('minimum and stroke-consumed bounds stay finite and nonnegative', () {
    for (final kind in ShapeKind.values) {
      for (final strokeWidth in [2.0, 1e300]) {
        final bounds = shapeTextBounds(kind, const Size.square(32), strokeWidth);
        expect(bounds.width.isFinite && bounds.height.isFinite, isTrue, reason: '$kind/$strokeWidth');
        expect(bounds.width, greaterThanOrEqualTo(0), reason: '$kind/$strokeWidth width');
        expect(bounds.height, greaterThanOrEqualTo(0), reason: '$kind/$strokeWidth height');
        if (strokeWidth == 2) {
          expect(bounds.width, greaterThan(0), reason: '$kind minimum width');
          expect(bounds.height, greaterThan(0), reason: '$kind minimum height');
        } else {
          expect(bounds.isEmpty, isTrue, reason: '$kind excessive stroke');
        }
        expect(bounds.center.dx, closeTo(16, 1e-9), reason: '$kind/$strokeWidth center x');
        expect(bounds.center.dy, closeTo(16, 1e-9), reason: '$kind/$strokeWidth center y');
      }
    }
  });
}
