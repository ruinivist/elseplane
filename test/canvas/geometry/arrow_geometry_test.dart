// Verifies pure canvas geometry independently of tools and widgets.
// Covers calculations shared by creation, rendering, and selection.

import 'package:elseplane/canvas/geometry/arrow_geometry.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
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
