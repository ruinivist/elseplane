// Verifies arrow creation drafts, handles, and cancellation.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/tools/arrow_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('arrow bends continuously toward the visual counterclockwise side', () {
    const directions = [
      (start: Offset.zero, end: Offset(100, 0), side: Offset(0, -1)),
      (start: Offset(100, 0), end: Offset.zero, side: Offset(0, 1)),
      (start: Offset(0, 100), end: Offset.zero, side: Offset(-1, 0)),
      (start: Offset.zero, end: Offset(0, 100), side: Offset(1, 0)),
    ];

    Offset bend(Offset start, Offset end) {
      final vector = end - start;
      final control = arrowControlPoint(start: start, end: end);
      return control - (start + vector * 0.5);
    }

    for (final direction in directions) {
      final offset = bend(direction.start, direction.end);
      expect(
        offset.dx * direction.side.dx + offset.dy * direction.side.dy,
        greaterThan(0),
      );
    }

    const start = Offset(40, 80);
    const firstEnd = Offset(340, 180);
    const secondEnd = Offset(340.1, 180.1);
    final firstBend = bend(start, firstEnd);
    final secondBend = bend(start, secondEnd);
    expect((secondBend - firstBend).distance, lessThan(0.1));
    expect(
      firstBend.dx * secondBend.dx + firstBend.dy * secondBend.dy,
      greaterThan(0),
    );
  });

  test('arrow tool previews, commits on up, and discards tiny drags', () {
    final committed = <ArrowElementData>[];
    final tool = ArrowTool(session: testSessionProvider(), onArrow: committed.add)
      ..setColor(const Color(0xffd85b5b))
      ..setStrokeStyle(ArrowStrokeStyle.dashed)
      ..setStrokeWidth(3);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    tool.onPointerDown(
      pointer.down(const Offset(10, 20)),
      const Offset(10, 20),
    );
    expect(tool.preview, isNotNull);
    tool.onPointerMove(
      pointer.move(const Offset(120, 80)),
      const Offset(120, 80),
    );
    expect(tool.preview!.geometry.start, const Offset(10, 20));
    expect(tool.preview!.geometry.end, const Offset(120, 80));
    expect(tool.preview!.color, const Color(0xffd85b5b));
    expect(tool.preview!.strokeStyle, ArrowStrokeStyle.dashed);
    expect(tool.preview!.strokeWidth, 3);
    expect(tool.preview!.showControls, isFalse);
    expect(tool.preview!.geometry.controls, [
      arrowControlPoint(start: const Offset(10, 20), end: const Offset(120, 80)),
    ]);
    expect(committed, isEmpty);

    tool.onPointerUp(
      pointer.up(),
      const Offset(120, 80),
    );
    expect(committed, hasLength(1));
    expect(committed.single.start, const Offset(10, 20));
    expect(committed.single.end, const Offset(120, 80));
    expect(committed.single.color, const Color(0xffd85b5b));
    expect(committed.single.strokeStyle, ArrowStrokeStyle.dashed);
    expect(committed.single.strokeWidth, 3);
    final resource = testArrowFixture(committed.single);
    final bounds = resource.bounds;
    resource.setStrokeWidth(arrowStrokeWidthMaximum);
    expect(resource.bounds, bounds);

    expect(tool.preview, isNull);

    final tinyPointer = TestPointer(2, PointerDeviceKind.mouse);
    tool
      ..onPointerDown(
        tinyPointer.down(const Offset(200, 200)),
        const Offset(200, 200),
      )
      ..onPointerUp(
        tinyPointer.up(),
        const Offset(202, 201),
      );
    expect(committed, hasLength(1));
    tool.dispose();
  });

  test('RMB presses pin controls and LMB release commits while RMB remains held', () {
    final committed = <ArrowElementData>[];
    final tool = ArrowTool(session: testSessionProvider(), onArrow: committed.add);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    tool.onPointerDown(pointer.down(Offset.zero), Offset.zero);
    void move(Offset position, int buttons) => tool.onPointerMove(pointer.move(position, buttons: buttons), position);

    move(const Offset(40, 60), kPrimaryButton);
    move(const Offset(40, 60), kPrimaryButton | kSecondaryButton);
    final snapshot = tool.preview!.geometry;
    expect(snapshot.controls, const [Offset(40, 60)]);
    expect(tool.preview!.showControls, isTrue);
    move(const Offset(70, 80), kPrimaryButton | kSecondaryButton);
    expect(tool.preview!.geometry.controls, snapshot.controls);
    move(const Offset(70, 80), kPrimaryButton);
    expect(committed, isEmpty);
    move(const Offset(70, 80), kPrimaryButton | kSecondaryButton);
    expect(tool.preview!.geometry.controls, const [Offset(40, 60), Offset(70, 80)]);
    expect(snapshot.controls, const [Offset(40, 60)]);
    move(const Offset(120, 20), kSecondaryButton);
    expect(tool.preview, isNull);
    expect(committed, hasLength(1));
    expect(committed.single.end, const Offset(120, 20));
    expect(committed.single.controls, const [Offset(40, 60), Offset(70, 80)]);
    tool.onPointerUp(pointer.up(), const Offset(150, 20));
    expect(committed, hasLength(1));
    expect(committed.single.end, const Offset(120, 20));

    tool.dispose();
  });

  test('canceling clears controls and secondary-only input does not draw', () {
    final committed = <ArrowElementData>[];
    final tool = ArrowTool(session: testSessionProvider(), onArrow: committed.add);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    tool.onPointerDown(pointer.down(Offset.zero, buttons: kSecondaryButton), Offset.zero);
    expect(tool.isDrawing, isFalse);
    pointer.up();
    for (final cancel in [tool.cancel, () => tool.onPointerCancel(pointer.cancel())]) {
      tool
        ..onPointerDown(pointer.down(Offset.zero, buttons: kPrimaryButton), Offset.zero)
        ..onPointerMove(
          pointer.move(const Offset(20, 40), buttons: kPrimaryButton | kSecondaryButton),
          const Offset(20, 40),
        );
      cancel();
      if (pointer.isDown) pointer.up();
      expect(tool.preview, isNull);
      expect(committed, isEmpty);
    }
    tool
      ..onPointerDown(pointer.down(Offset.zero, buttons: kPrimaryButton), Offset.zero)
      ..onPointerMove(pointer.move(const Offset(100, 0)), const Offset(100, 0));
    expect(tool.preview!.showControls, isFalse);
    tool.onPointerUp(pointer.up(), const Offset(100, 0));
    expect(committed.single.controls, [arrowControlPoint(start: Offset.zero, end: const Offset(100, 0))]);
    tool.dispose();
  });
}
