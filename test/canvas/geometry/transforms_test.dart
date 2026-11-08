// Verifies local coordinate conversion and point-to-segment distance.
// Covers the pure calculations used by editor transforms and hit testing.

import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/geometry/element_geometry.dart';
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

  test('media resizing clamps images and links at 200px and allows growth', () {
    for (final url in ['https://example.com/image.png', 'https://example.com/article']) {
      final shrunk = resizeMediaElement(
        MediaElementData(id: url, position: Offset.zero, width: 300, url: url),
        const Offset(-200, -200),
        1,
      );
      expect(shrunk.width, 200);

      final grown = resizeMediaElement(shrunk, const Offset(100, 100), 1);
      expect(grown.width, 300);
    }
  });
}
