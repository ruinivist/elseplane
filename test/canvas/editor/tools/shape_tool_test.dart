// Verifies shape creation bounds and minimum size.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/tools/shape_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shape tool normalizes drags and rejects undersized shapes', () {
    final shapes = <ShapeElementData>[];
    final tool = ShapeTool(session: testSessionProvider(), onShape: shapes.add)
      ..setKind(ShapeKind.hexagon)
      ..setStrokeColor(const Color(0xffdc3f3f))
      ..setFillColor(const Color(0xff2f6fde))
      ..setStrokeWidth(3);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    tool
      ..onPointerDown(
        pointer.down(const Offset(180, 140)),
        const Offset(180, 140),
      )
      ..onPointerMove(
        pointer.move(const Offset(40, 20)),
        const Offset(40, 20),
      );
    expect(tool.preview!.rect, const Rect.fromLTRB(40, 20, 180, 140));
    tool.onPointerUp(pointer.up(), const Offset(40, 20));

    expect(shapes, hasLength(1));
    expect(shapes.single.kind, ShapeKind.hexagon);
    expect(shapes.single.position, const Offset(40, 20));
    expect(shapes.single.size, const Size(140, 120));
    expect(shapes.single.strokeColor, const Color(0xffdc3f3f));
    expect(shapes.single.fillColor, const Color(0xff2f6fde));
    expect(shapes.single.strokeWidth, 3);
    expect(tool.preview, isNull);

    final tiny = TestPointer(2, PointerDeviceKind.mouse);
    tool
      ..onPointerDown(
        tiny.down(const Offset(200, 200)),
        const Offset(200, 200),
      )
      ..onPointerUp(tiny.up(), const Offset(220, 220));
    expect(shapes, hasLength(1));

    tool.dispose();
  });
}
