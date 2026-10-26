// Verifies pointer ownership, cancellation, and tool routing over canvas objects.
// Uses a measured viewport substitute and focused canvas integration.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_input.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EditorSession session;
  late CanvasInput input;
  late _Viewport viewport;

  setUp(() {
    session = EditorSession(
      CanvasDocument(
        background: CanvasBackgroundKind.plain,
        elements: [
          ShapeElementData(
            id: 'a',
            position: Offset.zero,
            size: const Size(100, 100),
            kind: ShapeKind.rectangle,
            strokeColor: const Color(0xff000000),
            strokeWidth: 2,
            fillColor: null,
          ),
          ShapeElementData(
            id: 'b',
            position: const Offset(200, 0),
            size: const Size(100, 100),
            kind: ShapeKind.rectangle,
            strokeColor: const Color(0xff000000),
            strokeWidth: 2,
            fillColor: null,
          ),
        ],
      ),
      initialColor: const Color(0xff000000),
    );
    viewport = _Viewport();
    input = CanvasInput(
      session: session,
      viewport: viewport,
      enabled: () => session.isLive,
      panSlop: (_) => 10,
      onCloseMenu: () {},
      onOpenMenu: (_, _) {},
      onEndEditing: ({commitMediaDraft = true}) {},
      onFocusElement: (_, {edit = false}) {},
      onPlace: (_) {},
      onStroke: (_) {},
      onArrow: (_) {},
      onShape: (_) {},
    );
  });
  tearDown(() {
    input.dispose();
    session.dispose();
  });

  test('takeover rejects old callbacks even after a new gesture on the same target', () {
    final first = TestPointer();
    final second = TestPointer(2);
    final oldTarget = input.target('a')
      ..pointerDown(first.down(const Offset(30, 30)), control: true)
      ..transform(() => session.move(['a'], const Offset(10, 0)));
    input.target('b').pointerDown(second.down(const Offset(230, 30)), control: true);
    oldTarget.transform(() => session.move(['a'], const Offset(100, 0)));
    input
      ..pointerUp(second.up())
      ..pointerUp(first.up());
    expect((session.element('a')! as ShapeElementData).position, const Offset(10, 0));
    final current = input.target('a')..pointerDown(first.down(const Offset(40, 30)), control: true);
    oldTarget.transform(() => session.move(['a'], const Offset(100, 0)));
    current.transform(() => session.move(['a'], const Offset(20, 0)));
    input.pointerUp(first.up());
    current.finish();
    expect((session.element('a')! as ShapeElementData).position, const Offset(30, 0));
    session.undo();
    expect((session.element('a')! as ShapeElementData).position, const Offset(10, 0));
    current.move(const Offset(100, 0));
    expect((session.element('a')! as ShapeElementData).position, const Offset(10, 0));
    session.undo();
    expect((session.element('a')! as ShapeElementData).position, Offset.zero);
  });

  for (final releaseFirst in [false, true]) {
    test('click promotions finish after callbacks with raw release first $releaseFirst', () {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      for (final id in ['a', 'b']) {
        final target = input.target(id)..pointerDown(pointer.down(const Offset(30, 30)));
        if (releaseFirst) input.pointerUp(pointer.up());
        target.activate();
        if (!releaseFirst) input.pointerUp(pointer.up());
      }
      expect(session.document.elements.map((value) => value.id), ['a', 'b']);
      session.undo();
      expect(session.document.elements.map((value) => value.id), ['b', 'a']);
      session.undo();
      expect(session.document.elements.map((value) => value.id), ['a', 'b']);
      session.redo();
      expect(session.document.elements.map((value) => value.id), ['b', 'a']);
      session.redo();
      expect(session.document.elements.map((value) => value.id), ['a', 'b']);
    });
  }

  test('an old completion cannot split a newer target transform', () {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final old = input.target('a')
      ..pointerDown(pointer.down(const Offset(30, 30)), control: true)
      ..transform(() => session.move(['a'], const Offset(10, 0)));
    input.pointerUp(pointer.up());
    old.finish();
    final current = input.target('b')
      ..pointerDown(pointer.down(const Offset(230, 30)), control: true)
      ..transform(() => session.move(['b'], const Offset(10, 0)));
    old.finish();
    current.transform(() => session.move(['b'], const Offset(20, 0)));
    input.pointerUp(pointer.up());
    current.finish();
    session.undo();
    expect((session.element('b')! as ShapeElementData).position, const Offset(200, 0));
    expect((session.element('a')! as ShapeElementData).position, const Offset(10, 0));
  });

  test('one finger does not steal a stylus stroke', () {
    input.chooseTool(CanvasTool.pen);
    final stylus = TestPointer(1, PointerDeviceKind.stylus);
    final touch = TestPointer(2);
    input
      ..pointerDown(stylus.down(const Offset(10, 10)))
      ..pointerDown(touch.down(const Offset(200, 200)))
      ..pointerMove(stylus.move(const Offset(40, 30)));
    expect(input.pen.active, isTrue);
    expect(input.pen.points.last.position, const Offset(40, 30));
    input
      ..pointerUp(touch.up())
      ..pointerUp(stylus.up());
    expect(input.pen.active, isFalse);
  });

  test('canceling touch marquee restores the previous selection', () {
    input.chooseTool(CanvasTool.select, touchSelectionEnabled: true);
    session.setSelection(['a']);
    final pointer = TestPointer();
    input
      ..pointerDown(pointer.down(const Offset(500, 300)))
      ..pointerMove(pointer.move(const Offset(600, 400)));
    expect(session.selectedIds, {'b'});
    input.pointerCancel(pointer.cancel());
    expect(session.selectedIds, {'a'});
    expect(input.marquee, isNull);
  });

  test('a removed and reinserted ID does not revive its old input binding', () {
    final value = session.element('a')!;
    final oldTarget = input.target('a');
    session
      ..remove(['a'])
      ..insert([value]);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    oldTarget
      ..pointerDown(pointer.down(const Offset(30, 30)))
      ..activate()
      ..move(const Offset(100, 0));
    expect(session.activeId, isNull);
    expect((session.element('a')! as ShapeElementData).position, Offset.zero);
  });

  testWidgets('pan cancellation keeps full initial displacement and never flings', (tester) async {
    final pointer = TestPointer();
    input
      ..pointerDown(pointer.down(const Offset(10, 10)))
      ..pointerMove(pointer.move(const Offset(15, 10)));
    expect(viewport.deltas, isEmpty);
    input.pointerMove(pointer.move(const Offset(30, 10)));
    expect(viewport.deltas, [const Offset(20, 0)]);
    input.pointerCancel(pointer.cancel());
    expect(viewport.ends, 0);
  });

  testWidgets('drawing tools receive drags started over text blocks', (
    tester,
  ) async {
    SharedPreferencesAsyncWeb.registerWith(null);
    const style = TextNodeStyle(
      fontFamily: 'Source Serif 4',
      color: Color(0xff201C1A),
    );
    await pumpCanvas(
      tester,
      TestLibraryStore(
        CanvasDocument(
          background: CanvasBackgroundKind.plain,
          elements: [
            TextElementData(
              id: 'drawing-surface',
              position: const Offset(100, 160),
              width: 240,
              height: 300,
              markdown: 'Drawing surface',
              style: style,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('toolbar-arrow')));
    await tester.pump();
    final arrowDrag = await tester.startGesture(
      const Offset(140, 200),
      kind: PointerDeviceKind.mouse,
    );
    await arrowDrag.moveTo(const Offset(300, 240));
    await tester.pump();
    expect(find.byKey(const ValueKey('arrow-preview')), findsOneWidget);
    await arrowDrag.up();
    await tester.pump();
    expect(find.byType(ArrowElementView), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toolbar-shape')));
    await tester.pump();
    final shapeDrag = await tester.startGesture(
      const Offset(140, 380),
      kind: PointerDeviceKind.mouse,
    );
    await shapeDrag.moveTo(const Offset(300, 420));
    await tester.pump();
    expect(find.byKey(const ValueKey('shape-preview')), findsOneWidget);
    await shapeDrag.up();
    await tester.pump();
    expect(find.byType(ShapeElementView), findsOneWidget);
  });
}

class _Viewport implements CanvasInputViewport {
  final deltas = <Offset>[];
  int ends = 0;
  @override
  double get scale => 1;
  @override
  Offset screenToCanvas(Offset position) => position;
  @override
  Offset globalToScreen(Offset position) => position;
  @override
  Iterable<String> overlapping(Rect rect) => ['b'];
  @override
  Iterable<String> hitTest(Offset position) => const [];
  @override
  void startPan(Offset position) {}
  @override
  void stopAnimation() {}
  @override
  void updatePan(Offset position, Offset delta) => deltas.add(delta);
  @override
  void endPan(Velocity velocity) => ends++;
}
