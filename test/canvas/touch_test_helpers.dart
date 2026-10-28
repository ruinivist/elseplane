// Checks rendered touch motion and frozen editor state on explicit display frames.
// Shared by navigation replays and tool ownership tests.

import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

// ---------- Fixtures and geometry ----------

const touchTolerance = 1e-6;
const touchLandmarks = [Offset(100, 180), Offset(380, 180), Offset(640, 440)];
typedef TouchTouches = (Offset, Offset);
typedef TouchView = ({Offset offset, double scale});
typedef TouchBounds = ({TouchView lower, TouchView upper});

List<Offset> paintedTouchLandmarks(WidgetTester tester) {
  final origin = tester.getTopLeft(find.byType(LazyCanvas));
  return [
    for (var i = 0; i < touchLandmarks.length; i++)
      tester.getTopLeft(
            find.byWidgetPredicate((widget) => widget is ShapeElementView && widget.data.id == 'landmark-$i'),
          ) -
          origin,
  ];
}

CanvasDocument touchDocument([List<CanvasElementData> elements = const []]) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    ...elements,
    for (var i = 0; i < touchLandmarks.length; i++)
      ShapeElementData(
        id: 'landmark-$i',
        kind: ShapeKind.rectangle,
        position: touchLandmarks[i],
        size: const Size.square(32),
        strokeColor: const Color(0xff000000),
        fillColor: null,
        strokeWidth: 2,
      ),
  ],
);

TouchView touchView(LazyCanvasController controller) => (offset: controller.offset, scale: controller.scale);

/// Derives the viewport directly from the initial and current finger geometry.
/// This oracle does not call the grid's incremental transform implementation.
TouchView expectedTouchView(TouchView start, TouchTouches initial, TouchTouches current) {
  final initialCenter = (initial.$1 + initial.$2) / 2;
  final currentCenter = (current.$1 + current.$2) / 2;
  final scale = start.scale * (current.$2 - current.$1).distance / (initial.$2 - initial.$1).distance;
  final anchor = start.offset + initialCenter / start.scale;
  return (offset: anchor - currentCenter / scale, scale: scale);
}

TouchView stationaryTouchView(TouchView start, TouchTouches initial, TouchTouches current) {
  final scale = expectedTouchView(start, initial, current).scale;
  final anchor = start.offset + initial.$1 / start.scale;
  return (offset: anchor - initial.$1 / scale, scale: scale);
}

// Compare against an independently bounded segment of stable viewport transforms.
TouchView permittedTouchView(TouchBounds bounds, List<Offset> painted) {
  final before = screenTouchPoints(bounds.lower);
  final after = screenTouchPoints(bounds.upper);
  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < before.length; i++) {
    final delta = after[i] - before[i];
    final observed = painted[i] - before[i];
    numerator += delta.dx * observed.dx + delta.dy * observed.dy;
    denominator += delta.distanceSquared;
  }
  final t = denominator == 0 ? 0.0 : (numerator / denominator).clamp(0.0, 1.0);
  final scale = bounds.lower.scale + (bounds.upper.scale - bounds.lower.scale) * t;
  final origin = Offset.lerp(-bounds.lower.offset * bounds.lower.scale, -bounds.upper.offset * bounds.upper.scale, t)!;
  return (offset: -origin / scale, scale: scale);
}

Offset paintedTouchPoint(List<Offset> painted, Offset world) {
  final scale = (painted[1].dx - painted[0].dx) / (touchLandmarks[1].dx - touchLandmarks[0].dx);
  return painted[0] + (world - touchLandmarks[0]) * scale;
}

Offset projectTouch(TouchView view, Offset canvasPosition) => (canvasPosition - view.offset) * view.scale;

List<Offset> screenTouchPoints(TouchView view) => touchLandmarks.map((point) => projectTouch(view, point)).toList();

void expectTouchView(TouchView actual, TouchView expected, String context) {
  expect((actual.offset - expected.offset).distance, lessThan(touchTolerance), reason: context);
  expect(actual.scale, closeTo(expected.scale, touchTolerance), reason: context);
}

/// Fails on the worst rendered deviation from the intended gesture path.
/// Used by every replay scenario and the harness's negative controls.
class TouchMotionReport {
  double maxError = 0;
  Duration worstTime = Duration.zero;
  String worstContext = '';

  void sample(Duration time, List<Offset> painted, TouchView intended, String context) {
    final error = painted.indexed
        .map((entry) => (entry.$2 - projectTouch(intended, touchLandmarks[entry.$1])).distance)
        .reduce(math.max);
    expect(error.isFinite, isTrue, reason: context);
    if (error > maxError) {
      maxError = error;
      worstTime = time;
      worstContext = context;
    }
  }

  void verify() {
    expect(maxError, lessThan(touchTolerance), reason: worstContext);
  }
}

// ---------- Display frames ----------

Future<void> _pumpFrames(
  WidgetTester tester,
  Duration duration,
  int frameHz,
  void Function(Duration, int) check,
) async {
  var previous = Duration.zero;
  for (var frame = 1; previous < duration; frame++) {
    final timestamp = Duration(microseconds: math.min(duration.inMicroseconds, (frame * 1000000 / frameHz).round()));
    await tester.pump(timestamp - previous);
    check(timestamp, frame);
    previous = timestamp;
  }
}

Future<void> _checkFrames(
  WidgetTester tester,
  Duration duration,
  int frameHz,
  TouchBounds Function(int) bounds,
  void Function(TouchView)? onFrame,
) async {
  final report = TouchMotionReport();
  TestFailure? stateFailure;
  await _pumpFrames(tester, duration, frameHz, (time, frame) {
    final painted = paintedTouchLandmarks(tester);
    final intended = permittedTouchView(bounds(frame), painted);
    report.sample(
      time,
      painted,
      intended,
      'frame $frame at ${time.inMicroseconds}us: expected=$intended painted=$painted',
    );
    try {
      onFrame?.call(intended);
    } on TestFailure catch (failure) {
      stateFailure ??= failure;
    }
  });
  if (stateFailure != null) throw stateFailure!;
  if (report.maxError >= touchTolerance) {
    debugPrint('touch frame error=${report.maxError.toStringAsFixed(3)}px: ${report.worstContext}');
  }
  report.verify();
}

Future<void> pumpTouchResponse(
  WidgetTester tester, {
  required TouchView previous,
  required TouchView target,
  int frameHz = 60,
  void Function(TouchView)? onFrame,
}) => _checkFrames(
  tester,
  Duration(microseconds: (2 * 1000000 / frameHz).round()),
  frameHz,
  (frame) => (lower: frame == 1 ? previous : target, upper: target),
  onFrame,
);

Future<void> pumpTouchHold(
  WidgetTester tester, {
  required TouchView expected,
  Duration duration = const Duration(milliseconds: 200),
  int frameHz = 60,
  void Function(TouchView)? onFrame,
}) => _checkFrames(tester, duration, frameHz, (_) => (lower: expected, upper: expected), onFrame);

List<Offset> _corners(WidgetTester tester, Finder element) => [
  tester.getTopLeft(element),
  tester.getTopRight(element),
  tester.getBottomLeft(element),
  tester.getBottomRight(element),
];

List<Offset> touchWorldCorners(WidgetTester tester, Finder element, TouchView view) {
  final origin = tester.getTopLeft(find.byType(LazyCanvas));
  return _corners(tester, element).map((point) => view.offset + (point - origin) / view.scale).toList();
}

void expectTouchWorldCorners(WidgetTester tester, Finder element, List<Offset> world, TouchView view) {
  final origin = tester.getTopLeft(find.byType(LazyCanvas));
  final actual = _corners(tester, element);
  for (var i = 0; i < world.length; i++) {
    expect(
      (actual[i] - origin - projectTouch(view, world[i])).distance,
      lessThan(touchTolerance),
      reason: 'frozen object corner $i',
    );
  }
}
