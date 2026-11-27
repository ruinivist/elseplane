// Verifies pure canvas geometry independently of tools and widgets.
// Covers calculations shared by creation, rendering, and selection.

import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/geometry/arrow_anchor_geometry.dart';
import 'package:elseplane/canvas/geometry/arrow_geometry.dart';
import 'package:elseplane/canvas/geometry/element_geometry.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  test('rectangular attachment points are exact side midpoints', () {
    const frame = ArrowAnchorFrame(body: Rect.fromLTWH(100, 200, 80, 40));
    expect(ArrowAnchorSide.values.map(frame.point), const [
      Offset(140, 200),
      Offset(180, 220),
      Offset(140, 240),
      Offset(100, 220),
    ]);
  });

  test('rotation transforms the points and containment around the body center', () {
    const frame = ArrowAnchorFrame(body: Rect.fromLTWH(100, 200, 80, 40), rotation: math.pi / 2);
    expect((frame.point(ArrowAnchorSide.top) - const Offset(160, 220)).distance, lessThan(1e-9));
    expect(frame.contains(const Offset(155, 245)), isTrue);
    expect(frame.contains(const Offset(165, 245)), isFalse);
  });

  test('nonrectangular sides intersect the outline, not the bounding box', () {
    const frame = ArrowAnchorFrame(body: Rect.fromLTWH(100, 200, 80, 40), shape: ShapeKind.triangle);
    expect((frame.point(ArrowAnchorSide.left) - const Offset(120, 220)).distance, lessThan(0.001));
    expect((frame.point(ArrowAnchorSide.right) - const Offset(160, 220)).distance, lessThan(0.001));
    expect(frame.contains(const Offset(121, 220)), isTrue);
    expect(frame.contains(const Offset(119, 220)), isFalse);
  });

  test('minimum length uses a finite direction even when both endpoints coincide', () {
    const fixed = Offset(2, 3);
    final point = minimumLengthArrowPoint(fixed, fixed, fixed);
    expect(point.dx - fixed.dx, allOf(greaterThanOrEqualTo(arrowMinimumLength), closeTo(arrowMinimumLength, 0.001)));
    expect(point.dy, fixed.dy);
    final withPreviousDirection = minimumLengthArrowPoint(fixed, fixed, fixed + const Offset(0, -1));
    expect(withPreviousDirection.dx, fixed.dx);
    expect(fixed.dy - withPreviousDirection.dy, closeTo(arrowMinimumLength, 0.001));
  });

  test('movement can keep a bound fallback while paste shifts all saved points', () {
    const attachment = ArrowAttachment(targetId: 'shape', side: ArrowAnchorSide.right);
    final arrow = ArrowElementData(
      id: 'arrow',
      start: Offset.zero,
      controls: const [Offset(40, 20)],
      end: const Offset(80, 0),
      color: const Color(0xffffffff),
      strokeStyle: ArrowStrokeStyle.solid,
      strokeWidth: 2,
      startAttachment: attachment,
    );
    const delta = Offset(30, 50);
    final moved = moveElement(arrow, delta, keepAttachedEndpoints: true) as ArrowElementData;
    expect(moved.start, arrow.start);
    expect(moved.end, arrow.end + delta);
    expect(moved.controls.single, arrow.controls.single + delta);
    expect(moved.startAttachment, attachment);
    final pasted = moveElement(arrow, delta) as ArrowElementData;
    expect(pasted.start, arrow.start + delta);
    expect(pasted.end, moved.end);
    expect(pasted.controls, moved.controls);
    expect(pasted.startAttachment, attachment);
  });

  test('joined curves stay smooth and later handles affect only nearby sections', () {
    final geometry = ArrowGeometry(
      start: Offset.zero,
      controls: const [Offset(40, 80), Offset(100, -40), Offset(180, 60)],
      end: const Offset(240, 0),
    );
    final changed = ArrowGeometry(
      start: geometry.start,
      controls: [geometry.controls[0], geometry.controls[1], const Offset(180, 120)],
      end: geometry.end,
    );
    final join = (geometry.controls[0] + geometry.controls[1]) / 2;
    final first = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(40, 80, join.dx, join.dy);
    final metric = geometry.shaftPath.computeMetrics().single;
    final firstLength = first.computeMetrics().single.length;
    final tangentBefore = metric.getTangentForOffset(firstLength - 0.01)!;
    final tangentAfter = metric.getTangentForOffset(firstLength + 0.01)!;
    expect((tangentBefore.position - join).distance, lessThan(0.1));
    expect((tangentAfter.position - join).distance, lessThan(0.1));
    expect((tangentBefore.vector - tangentAfter.vector).distance, lessThan(0.01));
    expect(
      changed.shaftPath.computeMetrics().single.getTangentForOffset(firstLength / 2)!.position,
      metric.getTangentForOffset(firstLength / 2)!.position,
    );

    final coincident = ArrowGeometry(
      start: Offset.zero,
      controls: const [Offset(100, 0), Offset(100, 0)],
      end: const Offset(100, 0),
    );
    expect(coincident.endTangent, const Offset(1, 0));
    expect(coincident.bounds.isFinite, isTrue);
  });
}
