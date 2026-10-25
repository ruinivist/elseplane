// Verifies local coordinate conversion and point-to-segment distance.
// Covers the pure calculations used by editor transforms and hit testing.

import 'dart:math' as math;

import 'package:elseplane/canvas/geometry/hit_test.dart';
import 'package:elseplane/canvas/geometry/transforms.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  test('screen deltas follow local axes at the current zoom and rotation', () {
    final delta = screenDeltaToLocal(const Offset(20, 10), scale: 2, rotation: math.pi / 2);
    expect(delta.dx, closeTo(5, 1e-9));
    expect(delta.dy, closeTo(-10, 1e-9));
    expect(screenDeltaToLocal(Offset.zero, scale: 2, rotation: math.pi), Offset.zero);
  });

  test('distance to a segment clamps endpoints and handles a point segment', () {
    expect(distanceToSegmentSquared(const Offset(-3, 4), Offset.zero, const Offset(10, 0)), 25);
    expect(distanceToSegmentSquared(const Offset(5, 4), Offset.zero, const Offset(10, 0)), 16);
    expect(distanceToSegmentSquared(const Offset(3, 4), Offset.zero, Offset.zero), 25);
  });
}
