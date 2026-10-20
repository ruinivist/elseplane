// Verifies pure canvas geometry independently of tools and widgets.
// Covers calculations shared by creation, rendering, and selection.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/geometry/pen_geometry.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  test('positions a screen stroke in canvas coordinates', () {
    final stroke = positionStroke(
      (
        points: const [
          PenPointData(Offset(100, 200), pressure: 0.5),
          PenPointData(Offset(200, 300), pressure: 0.5),
        ],
        color: const Color(0xff000000),
        width: 5.0,
        streamline: 0.75,
      ),
      id: 'pen',
      canvasOffset: const Offset(50, -20),
      canvasScale: 2,
    );

    expect(stroke.position, const Offset(94.5, 74.5));
    expect(stroke.size, const Size(61, 61));
    expect(stroke.hitSlop, 3);
    expect(stroke.width, 2.5);
    expect(stroke.streamline, 0.75);
    expect(stroke.points.first.position.dx, 5.5);
    expect(stroke.points.first.position.dy, 5.5);
  });
}
