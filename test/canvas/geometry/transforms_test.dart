// Verifies coordinate conversion and transformed selection overlap.
// Covers the pure calculations used by editor transforms and marquee selection.

import 'dart:math' as math;

import 'package:elseplane/canvas/geometry/hit_test.dart';
import 'package:elseplane/canvas/geometry/transforms.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/utils/conversions.dart';

// ---------- Tests ----------

void main() {
  test('screen deltas follow local axes at the current zoom and rotation', () {
    final delta = screenDeltaToLocal(const Offset(20, 10), scale: 2, rotation: math.pi / 2);
    expect(delta.dx, closeTo(5, 1e-9));
    expect(delta.dy, closeTo(-10, 1e-9));
    expect(screenDeltaToLocal(Offset.zero, scale: 2, rotation: math.pi), Offset.zero);
  });

  test('selection uses rotated measured bounds rather than the unrotated rectangle', () {
    final transform = childTransform(const Offset(100, 100), const Size(100, 40), math.pi / 2, scale: 2).storage;
    expect(transformedRectOverlaps(const Rect.fromLTWH(195, 45, 10, 10), const Size(100, 40), transform), isTrue);
    expect(transformedRectOverlaps(const Rect.fromLTWH(100, 100, 10, 10), const Size(100, 40), transform), isFalse);
    expect(transformedRectOverlaps(Rect.zero, const Size(100, 40), transform), isFalse);
  });

  test('distance to a segment clamps endpoints and handles a point segment', () {
    expect(distanceToSegmentSquared(const Offset(-3, 4), Offset.zero, const Offset(10, 0)), 25);
    expect(distanceToSegmentSquared(const Offset(5, 4), Offset.zero, const Offset(10, 0)), 16);
    expect(distanceToSegmentSquared(const Offset(3, 4), Offset.zero, Offset.zero), 25);
  });
}
