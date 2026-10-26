// Verifies pen creation samples, cancellation, and queued defaults.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/tools/pen_tool.dart';
import 'package:elseplane/canvas/geometry/pen_geometry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  test('pen normalizes pressure and filters non-owner or nearby points', () {
    final strokes = <RawPenStroke>[];
    final tool = PenTool(session: testSessionProvider(), onStroke: strokes.add)
      ..onPointerDown(
        const PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          pressureMin: 0.2,
          pressureMax: 0.8,
        ),
      )
      ..onPointerUpdate(
        const PointerMoveEvent(pointer: 2, position: Offset(10, 0)),
      )
      ..onPointerHover(
        const PointerHoverEvent(pointer: 2, position: Offset(10, 0)),
      )
      ..onPointerUp(
        const PointerUpEvent(pointer: 2, position: Offset(10, 0)),
      )
      ..onPointerUpdate(
        const PointerMoveEvent(pointer: 1, position: Offset(2, 0)),
      )
      ..onPointerUpdate(
        const PointerMoveEvent(
          pointer: 1,
          position: Offset(3, 0),
          pressure: 0.8,
          pressureMin: 0.2,
          pressureMax: 0.8,
        ),
      )
      ..onPointerUp(
        const PointerUpEvent(
          pointer: 1,
          position: Offset(6, 0),
          pressureMin: 0,
          pressureMax: 0,
        ),
      );

    expect(strokes, hasLength(1));
    expect(
      strokes.single.points.map((point) => point.position),
      const [Offset.zero, Offset(3, 0), Offset(6, 0)],
    );
    expect(strokes.single.points.first.pressure, closeTo(0.5, 0.0001));
    expect(strokes.single.points[1].pressure, closeTo(1, 0.0001));
    expect(strokes.single.points.last.pressure, 0.5);
    tool.dispose();
  });

  test('pen defers smoothing changes until the active stroke finishes', () {
    final strokes = <RawPenStroke>[];
    final tool = PenTool(session: testSessionProvider(), onStroke: strokes.add)
      ..onPointerDown(const PointerDownEvent(pointer: 1))
      ..setStreamline(1)
      ..onPointerUp(const PointerUpEvent(pointer: 1, position: Offset(4, 0)))
      ..onPointerDown(const PointerDownEvent(pointer: 2))
      ..onPointerUp(const PointerUpEvent(pointer: 2, position: Offset(4, 0)));

    expect(strokes.map((stroke) => stroke.streamline), [penStreamlineDefault, 1]);
    tool.dispose();
  });

  test('pen cancellation discards while mouse exit commits once', () {
    final strokes = <RawPenStroke>[];
    final tool = PenTool(session: testSessionProvider(), onStroke: strokes.add)
      ..onPointerDown(const PointerDownEvent(pointer: 1))
      ..onPointerCancel(
        const PointerCancelEvent(pointer: 1, position: Offset(4, 0)),
      )
      ..onPointerCancel(const PointerCancelEvent(pointer: 1))
      ..onPointerDown(
        const PointerDownEvent(pointer: 2, position: Offset(10, 0)),
      )
      ..onPointerExit(
        const PointerExitEvent(pointer: 2, position: Offset(14, 0)),
      )
      ..onPointerExit(const PointerExitEvent(pointer: 2));

    expect(strokes, hasLength(1));
    expect(tool.active, isFalse);
    tool.dispose();
  });

  test('discarded pen strokes apply queued options to the next stroke', () {
    final strokes = <RawPenStroke>[];
    final tool = PenTool(session: testSessionProvider(), onStroke: strokes.add)
      ..onPointerDown(const PointerDownEvent(pointer: 1))
      ..setColor(Colors.red)
      ..setStrokeWidth(8)
      ..setStreamline(1)
      ..cancel()
      ..onPointerUp(const PointerUpEvent(pointer: 1))
      ..onPointerDown(const PointerDownEvent(pointer: 2))
      ..onPointerUp(const PointerUpEvent(pointer: 2));
    expect(strokes, hasLength(1));
    expect(strokes.single.color, Colors.red);
    expect(strokes.single.width, 8);
    expect(strokes.single.streamline, 1);
    tool.dispose();
  });
}
