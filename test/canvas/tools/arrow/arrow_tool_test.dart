// Verifies arrow creation, editing, rendering, and toolbar behavior.
// Exercises the arrow tool through model and canvas widget flows.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_background.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/canvas/persistence/canvas_document_store.dart';
import 'package:elseplane/canvas/tools/arrow/arrow_tool.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../../test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    final preferences = SharedPreferencesAsync();
    await preferences.remove(CanvasDocumentStore.libraryKey);
  });

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
    final committed = <ArrowModel>[];
    final tool = ArrowTool(onArrow: committed.add)
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
    final bounds = committed.single.bounds;
    committed.single.strokeWidth = arrowStrokeWidthMaximum;
    expect(committed.single.bounds, bounds);
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
    committed.single.dispose();
  });

  test('RMB presses pin controls and LMB release commits while RMB remains held', () {
    final committed = <ArrowModel>[];
    final tool = ArrowTool(onArrow: committed.add);
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

    for (final model in committed) {
      model.dispose();
    }
    tool.dispose();
  });

  test('canceling clears controls and secondary-only input does not draw', () {
    final committed = <ArrowModel>[];
    final tool = ArrowTool(onArrow: committed.add);
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
    committed.single.dispose();
    tool.dispose();
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

  test('arrow points edit independently and preserve minimum length', () {
    final model = ArrowModel(
      ArrowElementData(
        id: 'arrow',
        start: const Offset(10, 20),
        controls: const [Offset(60, 5), Offset(80, 20)],
        end: const Offset(110, 40),
        color: Colors.black.toARGB32(),
        strokeStyle: ArrowStrokeStyle.solid,
        strokeWidth: 2,
      ),
    );

    final geometry = model.geometry;
    final copied = model.data.copy();
    expect(model.setPoint(1, const Offset(70, 10)), isTrue);
    expect(model.start, const Offset(10, 20));
    expect(model.controls, const [Offset(70, 10), Offset(80, 20)]);
    expect(geometry.controls, const [Offset(60, 5), Offset(80, 20)]);
    expect(copied.controls, geometry.controls);
    expect(model.end, const Offset(110, 40));

    model.setPoint(model.pointCount - 1, model.start);
    expect(
      (model.end - model.start).distance,
      greaterThanOrEqualTo(arrowMinimumLength),
    );
    expect(
      () => ArrowElementData.fromJson(model.data.toJson()),
      returnsNormally,
    );
    model.dispose();
  });

  testWidgets('active arrows expose zoom-aware editable points with one-step undo', (tester) async {
    await pumpCanvas(tester, TestCanvasDocumentStore(_arrowDocument()));
    final arrowFinder = find.byType(Arrow);
    var model = tester.widget<Arrow>(arrowFinder).model;

    expect(find.byKey(const ValueKey('arrow-start-handle')), findsNothing);
    final curvePoint = model.start * 0.25 + model.controls.single * 0.5 + model.end * 0.25;
    await tester.tapAt(
      tester.getTopLeft(arrowFinder) + curvePoint - model.bounds.topLeft,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('arrow-bezier-guides')), findsOneWidget);
    expect(find.byKey(const ValueKey('arrow-start-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('arrow-control-0-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('arrow-end-handle')), findsOneWidget);

    final originalEnd = model.end;
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    canvas.controller.updateScalebyDelta(1, focalPoint: Offset.zero);
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('arrow-end-handle')),
      const Offset(40, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(model.end, originalEnd + const Offset(20, 10));
    expect(
      canvas.controller.widgetsWithScreenPositions().single.gsPosition,
      model.canvasPosition,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    model = tester.widget<Arrow>(arrowFinder).model;
    expect(model.end, originalEnd);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('arrow-control-0-handle')), findsNothing);
  });

  testWidgets('multi-handle dragging stays on canvas, edits at zoom, saves and undoes', (tester) async {
    final store = TestCanvasDocumentStore(const CanvasDocument(background: CanvasBackgroundKind.plain, elements: []));
    await pumpCanvas(tester, store);
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
      ..updateScalebyDelta(1, focalPoint: Offset.zero);
    await tester.tap(find.byKey(const ValueKey('toolbar-arrow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('arrow-style-dashed')));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.down(const Offset(120, 300)));
    await tester.sendEventToBinding(pointer.move(const Offset(200, 300), buttons: kPrimaryButton | kSecondaryButton));
    await tester.pump();
    final preview =
        tester.widget<CustomPaint>(find.byKey(const ValueKey('arrow-preview'))).painter! as ArrowPreviewPainter;
    expect(preview.preview.showControls, isTrue);
    expect(preview.preview.geometry.controls, const [Offset(100, 150)]);
    await tester.sendEventToBinding(pointer.move(const Offset(360, 220), buttons: kPrimaryButton));
    await tester.sendEventToBinding(pointer.move(const Offset(360, 220), buttons: kPrimaryButton | kSecondaryButton));
    await tester.sendEventToBinding(pointer.move(const Offset(520, 340), buttons: kSecondaryButton));
    await tester.pump();
    expect(controller.offset, Offset.zero);
    expect(find.byKey(const ValueKey('arrow-preview')), findsNothing);
    expect(find.byType(Arrow), findsOneWidget);
    expect(tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-arrow'))).selected, isFalse);
    var model = tester.widget<Arrow>(find.byType(Arrow)).model;
    expect(model.active, isTrue);
    expect(model.controls, const [Offset(100, 150), Offset(180, 110)]);
    expect(model.end, const Offset(260, 170));
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();
    expect(find.byType(Arrow), findsOneWidget);
    expect(find.byKey(const ValueKey('arrow-control-0-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('arrow-control-1-handle')), findsOneWidget);

    final paint = tester
        .widget<CustomPaint>(find.descendant(of: find.byType(Arrow), matching: find.byType(CustomPaint)))
        .foregroundPainter!;
    final metric = model.localGeometry.shaftPath.computeMetrics().single;
    for (final fraction in [0.25, 0.5, 0.75]) {
      expect(paint.hitTest(metric.getTangentForOffset(metric.length * fraction)!.position), isTrue);
    }
    final original = model.controls;
    await tester.drag(
      find.byKey(const ValueKey('arrow-control-1-handle')),
      const Offset(40, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.controls, [original[0], original[1] + const Offset(20, 10)]);
    await pumpPastSave(tester);
    expect((store.persisted!.elements.single as ArrowElementData).controls, model.controls);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    model = tester.widget<Arrow>(find.byType(Arrow)).model;
    expect(model.controls, original);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    model = tester.widget<Arrow>(find.byType(Arrow)).model;
    expect(model.controls, [original[0], original[1] + const Offset(20, 10)]);

    final pan = await tester.startGesture(
      const Offset(600, 400),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await pan.moveBy(const Offset(40, 20));
    await pan.up();
    expect(controller.offset, isNot(Offset.zero));
  });

  testWidgets('inactive arrow dragging preserves layers and activation requires a click', (tester) async {
    final store = TestCanvasDocumentStore(_arrowDocument());
    await pumpCanvas(tester, store);
    final model = tester.widget<Arrow>(find.byType(Arrow)).model;
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final order = canvas.childOrder;
    const delta = Offset(50, 30);
    final drag = await tester.startGesture(model.start, kind: PointerDeviceKind.mouse);
    await drag.moveBy(delta);
    await tester.pump();
    expect(model.active, isFalse);
    expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).foregroundChildId, isNull);
    await drag.up();
    await tester.pumpAndSettle();
    expect(model.active, isFalse);
    expect(model.selected, isFalse);
    expect(canvas.childOrder, order);
    model.selected = true;
    await tester.tapAt(model.start);
    await tester.pumpAndSettle();
    expect(model.active, isTrue);
    expect(model.selected, isFalse);
    expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).foregroundChildId, model.data.id);
    expect(canvas.childOrder, order);
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('$platform arrow menu dismissal preserves modifier selection and group dragging', (tester) async {
      final document = _arrowDocument();
      document.elements.add(
        ArrowElementData(
          id: 'other',
          start: const Offset(480, 350),
          controls: const [Offset(550, 300)],
          end: const Offset(650, 390),
          color: Colors.black.toARGB32(),
          strokeStyle: ArrowStrokeStyle.solid,
          strokeWidth: 2,
        ),
      );
      await pumpCanvas(tester, TestCanvasDocumentStore(document), platform: platform);
      final models = tester.widgetList<Arrow>(find.byType(Arrow)).map((arrow) => arrow.model).toList();
      final first = models.first;
      final second = models.last;
      first.selected = true;
      second.selected = true;
      Future<void> openMenu() async {
        final click = await tester.startGesture(second.start, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
        await click.up();
        await tester.pumpAndSettle();
        expect(find.byType(MenuSurface), findsOneWidget);
      }

      await openMenu();
      await tester.tapAt(first.start);
      await tester.pumpAndSettle();
      expect(find.byType(MenuSurface), findsNothing);
      expect(first.active, isTrue);
      expect(models.every((model) => !model.selected), isTrue);

      await openMenu();
      final modifier = platform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.pump();
      await tester.tapAt(first.start);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(find.byType(MenuSurface), findsNothing);
      expect(models.every((model) => model.selected && !model.active), isTrue);

      await openMenu();
      final starts = models.map((model) => model.start).toList();
      const delta = Offset(30, 20);
      await tester.dragFrom(first.start, delta);
      await tester.pumpAndSettle();
      expect(find.byType(MenuSurface), findsNothing);
      for (var index = 0; index < models.length; index++) {
        expect(models[index].start, starts[index] + delta);
        expect(models[index].selected, isTrue);
        expect(models[index].active, isFalse);
      }
    });
  }

  testWidgets('arrows place once, activate by click, select by marquee, and move', (
    tester,
  ) async {
    await pumpElseplaneApp(tester);

    await tester.tap(find.byKey(const ValueKey('toolbar-arrow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('arrow-settings-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('arrow-style-dashed')));
    await tester.tap(find.byKey(const ValueKey('color-preset-Red')));
    tester.widget<Slider>(find.byKey(const ValueKey('discrete-slider'))).onChanged!(3);
    await tester.pump();
    final firstDrag = await tester.startGesture(
      const Offset(120, 200),
      kind: PointerDeviceKind.mouse,
    );
    await firstDrag.moveTo(const Offset(300, 260));
    await tester.pump();
    expect(find.byKey(const ValueKey('arrow-preview')), findsOneWidget);
    expect(find.byType(Arrow), findsNothing);
    await firstDrag.up();
    await tester.pump();

    expect(find.byType(Arrow), findsOneWidget);
    final first = tester.widget<Arrow>(find.byType(Arrow)).model;
    expect(first.start, const Offset(120, 200));
    expect(first.end, const Offset(300, 260));
    expect(first.strokeStyle, ArrowStrokeStyle.dashed);
    expect(
      first.color.toARGB32(),
      presetColors.firstWhere((swatch) => swatch.label == 'Red').color.toARGB32(),
    );
    expect(first.strokeWidth, 3);
    expect(find.byKey(const ValueKey('arrow-settings-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('arrow-style-solid')));
    await tester.pump();
    expect(first.strokeStyle, ArrowStrokeStyle.solid);
    final toolbar = find.byKey(const ValueKey('toolbar-arrow'));
    expect(tester.widget<ToolbarButton>(toolbar).selected, isFalse);

    final secondDrag = await tester.startGesture(
      const Offset(420, 200),
      kind: PointerDeviceKind.mouse,
    );
    await secondDrag.moveTo(const Offset(560, 260));
    await secondDrag.up();
    await tester.pump();
    expect(find.byType(Arrow), findsOneWidget);

    final arrowFinder = find.byType(Arrow).first;
    final arrowTopLeft = tester.getTopLeft(arrowFinder);
    final startPoint =
        arrowTopLeft +
        Offset(
          first.start.dx - first.bounds.left,
          first.start.dy - first.bounds.top,
        );
    await tester.tapAt(startPoint);
    await tester.pump();
    expect(first.active, isTrue);
    expect(first.selected, isFalse);
    expect(find.byKey(const ValueKey('arrow-block-handle')), findsWidgets);
    expect(find.byKey(const ValueKey('arrow-block-delete-control')), findsWidgets);
    expect(find.byKey(const ValueKey('arrow-block-rotate-control')), findsNothing);

    const moveDelta = Offset(40, 30);
    final move = await tester.startGesture(
      startPoint,
      kind: PointerDeviceKind.mouse,
    );
    await move.moveBy(moveDelta);
    await move.up();
    await tester.pump();
    expect(first.start, const Offset(160, 230));

    final marquee = await tester.startGesture(
      const Offset(80, 150),
      kind: PointerDeviceKind.mouse,
    );
    await marquee.moveTo(const Offset(350, 330));
    await tester.pump();
    expect(first.selected, isTrue);
    await marquee.up();
  });
}

CanvasDocument _arrowDocument() => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    ArrowElementData(
      id: 'arrow',
      start: const Offset(120, 200),
      controls: const [Offset(210, 160)],
      end: const Offset(300, 240),
      color: Colors.black.toARGB32(),
      strokeStyle: ArrowStrokeStyle.solid,
      strokeWidth: 2,
    ),
  ],
);
