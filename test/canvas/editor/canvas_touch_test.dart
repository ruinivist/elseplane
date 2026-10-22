// Verifies touch ownership between canvas tools, object edits, and navigation.
// Exercises elseplane's handoff through real pointer sequences and persisted models.

import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/canvas/tools/arrow/arrow_tool.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/media/media_tool.dart';
import 'package:elseplane/canvas/tools/pen/pen_tool.dart';
import 'package:elseplane/canvas/tools/shape/shape_tool.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  testWidgets('empty touch pans after slop, preserves selection, and converts zoom', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_pen('a')])));
    final model = tester.widget<PenStroke>(find.byType(PenStroke)).model..selected = true;
    final controller = _canvas(tester)..updateScalebyDelta(1);
    final before = controller.offset;
    final first = await tester.startGesture(const Offset(550, 400));
    await first.moveBy(const Offset(5, 0));
    expect(controller.offset, before);
    expect(model.selected, isTrue);
    await first.moveBy(const Offset(35, 20));
    expect(controller.offset, before - const Offset(40, 20) / controller.scale);
    await first.moveBy(const Offset(20, 10));
    expect(controller.offset, before - const Offset(60, 30) / controller.scale);
    expect(model.selected, isTrue);
    expect(model.data.position, const Offset(100, 250));
    await first.up();
  });

  testWidgets('empty touch tap clears activation and selection only on release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_code()])));
    final model = tester.widget<CodeTool>(find.byType(CodeTool)).model;
    await tester.tapAt(const Offset(220, 300));
    await tester.pumpAndSettle();
    model.selected = true;
    final touch = await tester.startGesture(const Offset(550, 400));
    await touch.moveBy(const Offset(5, 0));
    expect(model.active, isTrue);
    expect(model.selected, isTrue);
    expect(_canvas(tester).offset, Offset.zero);
    await touch.up();
    await tester.pump();
    expect(model.active, isFalse);
    expect(model.selected, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
  });

  for (final displacement in [Offset.zero, const Offset(60, 30)]) {
    testWidgets('canceling empty touch at $displacement preserves selection without inertia', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document([_pen('a')])));
      final model = tester.widget<PenStroke>(find.byType(PenStroke)).model..selected = true;
      final controller = _canvas(tester);
      final touch = await tester.startGesture(const Offset(550, 400));
      await touch.moveBy(displacement, timeStamp: const Duration(milliseconds: 16));
      await touch.moveBy(displacement, timeStamp: const Duration(milliseconds: 32));
      await touch.cancel();
      final frozen = controller.offset;
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.offset, frozen);
      expect(model.selected, isTrue);
      final fresh = await tester.startGesture(const Offset(550, 400));
      await fresh.moveBy(const Offset(40, 20));
      expect(controller.offset, frozen - const Offset(40, 20));
      await fresh.cancel();
    });
  }

  testWidgets('normal empty touch pan release uses viewport inertia', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    final controller = _canvas(tester);
    final touch = await tester.startGesture(const Offset(200, 300));
    for (var frame = 1; frame <= 5; frame++) {
      await touch.moveBy(const Offset(20, 0), timeStamp: Duration(milliseconds: frame * 16));
    }
    await touch.up(timeStamp: const Duration(milliseconds: 81));
    final released = controller.offset;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset.dx, lessThan(released.dx));
    expect(controller.scale, 1);
    controller.stopAnimation();
  });

  for (final displacement in [Offset.zero, const Offset(60, 30)]) {
    testWidgets('two fingers take over empty touch at $displacement without a jump or fling', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document([_pen('a')])));
      final model = tester.widget<PenStroke>(find.byType(PenStroke)).model..selected = true;
      final controller = _canvas(tester);
      final first = await tester.startGesture(const Offset(200, 400), pointer: 1);
      await first.moveBy(displacement, timeStamp: const Duration(milliseconds: 16));
      final panned = (controller.offset, controller.scale);
      final second = await tester.startGesture(const Offset(550, 400), pointer: 2);
      expect((controller.offset, controller.scale), panned);
      await second.moveBy(const Offset(60, 30));
      expect((controller.offset, controller.scale), isNot(panned));
      await second.up();
      final frozen = (controller.offset, controller.scale);
      await first.moveBy(const Offset(60, 30));
      await first.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect((controller.offset, controller.scale), frozen);
      expect(model.selected, isTrue);
      final fresh = await tester.startGesture(const Offset(550, 400));
      await fresh.moveBy(const Offset(40, 20));
      expect(controller.offset, frozen.$1 - const Offset(40, 20) / controller.scale);
      await fresh.cancel();
    });
  }

  testWidgets('tool changes cancel empty touch pan through final release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    final controller = _canvas(tester);
    final touch = await tester.startGesture(const Offset(200, 300));
    await touch.moveBy(const Offset(60, 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    final frozen = controller.offset;
    await touch.moveBy(const Offset(60, 30));
    await touch.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, frozen);
    expect(find.byType(PenStroke), findsNothing);
  });

  testWidgets('document replacement cancels an empty touch pan', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_pen('a')])));
    await tester.dragFrom(const Offset(150, 300), const Offset(60, 30));
    await tester.pump();
    final controller = _canvas(tester);
    final touch = await tester.startGesture(const Offset(550, 400));
    await touch.moveBy(const Offset(60, 30));
    await _undo(tester);
    final frozen = controller.offset;
    await touch.moveBy(const Offset(60, 30));
    await touch.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, frozen);
    expect(tester.widget<PenStroke>(find.byType(PenStroke)).model.data.position, const Offset(100, 250));
  });

  for (final select in [false, true]) {
    testWidgets('touch object movement with Select $select leaves the viewport fixed', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document([_pen('a')])), platform: TargetPlatform.android);
      if (select) await _chooseTool(tester, 'select');
      final model = tester.widget<PenStroke>(find.byType(PenStroke)).model;
      await tester.dragFrom(const Offset(150, 300), const Offset(60, 30));
      expect(model.data.position, isNot(const Offset(100, 250)));
      expect((_canvas(tester).offset, _canvas(tester).scale), (Offset.zero, 1));
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('Select is initially visible and accessible on $platform', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document()), platform: platform);
      final button = tester.getSemantics(
        find.descendant(of: find.byKey(const ValueKey('toolbar-select')), matching: find.byType(TextButton)),
      );
      expect(button.label, 'Select');
      expect(button.flagsCollection.isButton, isTrue);
      expect(find.byTooltip('Select elements'), findsOneWidget);
      expect(_selectEnabled(tester), isFalse);
    });
  }

  testWidgets('narrow mouse and stylus sessions keep the existing toolbar', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpCanvas(tester, TestLibraryStore(_document()), platform: TargetPlatform.linux);
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.stylus]) {
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('toolbar-draw'))),
        kind: kind,
      );
      await pointer.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('toolbar-select')), findsNothing);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(find.byKey(const ValueKey('toolbar-select')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop toolbar touch reveals Select after all releases and keeps it until reload', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()), platform: TargetPlatform.linux);
    final draw = find.byKey(const ValueKey('toolbar-draw'));
    final bounds = tester.getRect(draw);
    final toolbarTouch = await tester.startGesture(bounds.center, pointer: 1);
    final canvasTouch = await tester.startGesture(const Offset(550, 400), pointer: 2);
    await tester.pump();
    expect(find.byKey(const ValueKey('toolbar-select')), findsNothing);
    await toolbarTouch.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('toolbar-select')), findsNothing);
    expect(tester.getRect(draw), bounds);
    expect(tester.widget<ToolbarButton>(draw).selected, isTrue);
    await canvasTouch.cancel();
    await tester.pump();
    expect(find.byKey(const ValueKey('toolbar-select')), findsOneWidget);
    final mouse = await tester.startGesture(const Offset(550, 400), kind: PointerDeviceKind.mouse);
    await mouse.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('toolbar-select')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpCanvas(tester, TestLibraryStore(_document()), platform: TargetPlatform.linux);
    expect(find.byKey(const ValueKey('toolbar-select')), findsNothing);
  });

  testWidgets('browser touch reveals Select after all releases even when Flutter receives only a semantics tap', (
    tester,
  ) async {
    await pumpCanvas(tester, TestLibraryStore(_document()), platform: TargetPlatform.linux);
    void pointer(String type, int id, {String kind = 'touch'}) {
      web.document.dispatchEvent(web.PointerEvent(type, web.PointerEventInit(pointerId: id, pointerType: kind)));
    }

    pointer('pointerdown', 1, kind: 'pen');
    pointer('pointerup', 1, kind: 'pen');
    await tester.pump();
    expect(find.byKey(const ValueKey('toolbar-select')), findsNothing);
    pointer('pointerdown', 1);
    pointer('pointerdown', 2);
    pointer('pointerup', 1);
    await tester.pump();
    expect(find.byKey(const ValueKey('toolbar-select')), findsNothing);
    pointer('pointercancel', 2);
    // A semantic action can follow the browser pointer release synchronously.
    tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).onPressed!();
    await tester.pump(Duration.zero);
    expect(find.byKey(const ValueKey('toolbar-select')), findsOneWidget);
    expect(tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected, isTrue);
  });

  testWidgets('Select uses touch slop, stays enabled, and toggles back to panning without clearing selection', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      TestLibraryStore(_document([_pen('a'), _pen('b', const Offset(350, 250))])),
      platform: TargetPlatform.android,
    );
    await _chooseTool(tester, 'select');
    final models = tester.widgetList<PenStroke>(find.byType(PenStroke)).map((stroke) => stroke.model).toList();
    models[1].selected = true;
    final touch = await tester.startGesture(const Offset(60, 200));
    await touch.moveBy(const Offset(5, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('drag-selection-marquee')), findsNothing);
    expect(models[1].selected, isTrue);
    await touch.moveTo(const Offset(250, 350));
    await tester.pump();
    expect(find.byKey(const ValueKey('drag-selection-marquee')), findsOneWidget);
    expect(models.map((model) => model.selected), [true, false]);
    await touch.up();
    await tester.pump();
    expect(_selectEnabled(tester), isTrue);
    expect(find.byKey(const ValueKey('drag-selection-marquee')), findsNothing);
    expect(_canvas(tester).offset, Offset.zero);
    await _chooseTool(tester, 'select');
    expect(models[0].selected, isTrue);
    final pan = await tester.startGesture(const Offset(550, 400));
    await pan.moveBy(const Offset(40, 20));
    expect(_canvas(tester).offset, const Offset(-40, -20));
    expect(models[0].selected, isTrue);
    await pan.cancel();
  });

  testWidgets('Select empty tap clears activation and selection on release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_code()])), platform: TargetPlatform.android);
    await _chooseTool(tester, 'select');
    final model = tester.widget<CodeTool>(find.byType(CodeTool)).model;
    await tester.tapAt(const Offset(220, 300));
    await tester.pumpAndSettle();
    model.selected = true;
    final touch = await tester.startGesture(const Offset(550, 400));
    await touch.moveBy(const Offset(5, 0));
    expect((model.active, model.selected), (true, true));
    await touch.up();
    await tester.pump();
    expect((model.active, model.selected), (false, false));
    expect(_selectEnabled(tester), isTrue);
    await tester.pump(const Duration(milliseconds: 150));
  });

  for (final interruption in ['cancel', 'navigation', 'tool']) {
    testWidgets('$interruption restores prior touch selection and removes the marquee', (tester) async {
      await pumpCanvas(
        tester,
        TestLibraryStore(_document([_pen('a'), _pen('b', const Offset(350, 250))])),
        platform: TargetPlatform.android,
      );
      await _chooseTool(tester, 'select');
      final models = tester.widgetList<PenStroke>(find.byType(PenStroke)).map((stroke) => stroke.model).toList();
      models[1].selected = true;
      final touch = await tester.startGesture(const Offset(60, 200), pointer: 1);
      await touch.moveTo(const Offset(250, 350));
      expect(models.map((model) => model.selected), [true, false]);
      if (interruption == 'cancel') {
        await touch.cancel();
      } else if (interruption == 'navigation') {
        final second = await tester.startGesture(const Offset(550, 400), pointer: 2);
        expect(models.map((model) => model.selected), [false, true]);
        await second.moveBy(const Offset(40, 20));
        await second.up();
        final frozen = (_canvas(tester).offset, _canvas(tester).scale);
        await touch.moveBy(const Offset(60, 30));
        expect((_canvas(tester).offset, _canvas(tester).scale), frozen);
        await touch.up();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
        await touch.moveBy(const Offset(60, 30));
        await touch.up();
      }
      await tester.pump();
      expect(models.map((model) => model.selected), [false, true]);
      expect(find.byKey(const ValueKey('drag-selection-marquee')), findsNothing);
      expect(_selectEnabled(tester), interruption != 'tool');
    });
  }

  testWidgets('Select cancels drawing and other tools reset touch selection', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()), platform: TargetPlatform.android);
    await _chooseTool(tester, 'draw');
    final drawing = await tester.startGesture(const Offset(200, 300), pointer: 1);
    await drawing.moveBy(const Offset(40, 20));
    await _chooseTool(tester, 'select');
    await drawing.moveBy(const Offset(40, 20));
    await drawing.up();
    await tester.pump();
    expect(find.byType(PenStroke), findsNothing);
    expect(_selectEnabled(tester), isTrue);
    await _chooseTool(tester, 'shape');
    expect(_selectEnabled(tester), isFalse);
    await tester.dragFrom(const Offset(200, 300), const Offset(80, 60));
    await tester.pump();
    expect(find.byType(Shape), findsOneWidget);
    expect(_selectEnabled(tester), isFalse);
  });

  for (final touchSelect in [false, true]) {
    testWidgets('Escape deselects inactive objects with touch Select $touchSelect', (tester) async {
      final store = TestLibraryStore(_document([_pen('a'), _pen('b', const Offset(350, 250))]));
      await pumpCanvas(tester, store, platform: touchSelect ? TargetPlatform.android : TargetPlatform.linux);
      if (touchSelect) await _chooseTool(tester, 'select');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final models = tester.widgetList<PenStroke>(find.byType(PenStroke)).map((stroke) => stroke.model).toList();
      expect(models.every((model) => model.selected && !model.active), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(models.every((model) => !model.selected), isTrue);
      if (touchSelect) expect(_selectEnabled(tester), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await pumpPastSave(tester);
      expect(_canvas(tester).childOrder, ['a', 'b']);
      expect(store.persisted, isNull);
    });
  }

  testWidgets('Escape dismisses editing before disabling Select', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_code()])), platform: TargetPlatform.android);
    await _chooseTool(tester, 'select');
    await tester.tapAt(const Offset(220, 300));
    await tester.pumpAndSettle();
    final model = tester.widget<CodeTool>(find.byType(CodeTool)).model;
    expect(model.active, isTrue);
    model.selected = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(model.active, isFalse);
    expect(model.selected, isFalse);
    expect(_selectEnabled(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_selectEnabled(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('mixed touch group moves in either mode as one undo step and preserves Select', (tester) async {
    await pumpCanvas(
      tester,
      TestLibraryStore(
        _document([
          _pen('pen'),
          ShapeElementData(
            id: 'shape',
            kind: ShapeKind.rectangle,
            position: const Offset(300, 250),
            size: const Size(100, 100),
            strokeColor: const Color(0xff000000),
            fillColor: null,
            strokeWidth: 2,
          ),
          ArrowElementData(
            id: 'arrow',
            start: const Offset(450, 300),
            controls: const [Offset(500, 300)],
            end: const Offset(550, 300),
            color: const Color(0xff000000),
            strokeStyle: ArrowStrokeStyle.solid,
            strokeWidth: 3,
          ),
        ]),
      ),
      platform: TargetPlatform.android,
    );
    List<Offset> positions() => [
      tester.widget<PenStroke>(find.byType(PenStroke)).model.data.position,
      tester.widget<Shape>(find.byType(Shape)).model.data.position,
      tester.widget<Arrow>(find.byType(Arrow)).model.data.start,
    ];
    final before = positions();
    for (final select in [false, true]) {
      if (select) await _chooseTool(tester, 'select');
      tester.widget<PenStroke>(find.byType(PenStroke)).model.selected = true;
      tester.widget<Shape>(find.byType(Shape)).model.selected = true;
      tester.widget<Arrow>(find.byType(Arrow)).model.selected = true;
      final move = await tester.startGesture(before[0] + const Offset(50, 50));
      await move.moveBy(const Offset(40, 20));
      await move.moveBy(const Offset(30, 10));
      await move.up();
      final moved = positions();
      final delta = moved[0] - before[0];
      expect(delta, isNot(Offset.zero));
      expect(moved, before.map((position) => position + delta));
      await _undo(tester);
      expect(positions(), before);
      expect(_selectEnabled(tester), select);
      if (select) {
        await _undo(tester);
        expect(_selectEnabled(tester), isFalse);
      }
    }
  });

  testWidgets('touch marquee overlaps rotated bounds at non-default zoom', (tester) async {
    final code = _code().copyWith(position: const Offset(160, 140), rotation: math.pi / 2, title: '');
    await pumpCanvas(tester, TestLibraryStore(_document([code])), platform: TargetPlatform.android);
    await _chooseTool(tester, 'select');
    final controller = _canvas(tester)..updateScalebyDelta(0.5, focalPoint: Offset.zero);
    await tester.pump();
    final before = controller.offset;
    // This box hits the rotated top edge, above the unrotated screen bounds.
    final touch = await tester.startGesture(const Offset(415, 175));
    await touch.moveTo(const Offset(475, 205));
    await touch.up();
    await tester.pump();
    final model = tester.widget<CodeTool>(find.byType(CodeTool)).model;
    expect(model.selected, isTrue);
    expect(model.active, isFalse);
    expect(controller.offset, before);
    expect(_selectEnabled(tester), isTrue);
  });

  testWidgets('mouse marquee and modifier selection retain their behavior with Select enabled', (tester) async {
    await pumpCanvas(
      tester,
      TestLibraryStore(_document([_pen('a'), _pen('b', const Offset(350, 250))])),
      platform: TargetPlatform.linux,
    );
    final models = tester.widgetList<PenStroke>(find.byType(PenStroke)).map((stroke) => stroke.model).toList();
    Future<void> marquee(Offset end) async {
      final mouse = await tester.startGesture(const Offset(60, 200), kind: PointerDeviceKind.mouse);
      await mouse.moveTo(end);
      await mouse.up();
      await tester.pump();
    }

    await marquee(const Offset(250, 350));
    expect(models.map((model) => model.selected), [true, false]);
    expect(find.byKey(const ValueKey('toolbar-select')), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(const Offset(400, 300), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(models.map((model) => model.selected), [true, true]);
    final reveal = await tester.startGesture(const Offset(550, 400));
    await reveal.cancel();
    await tester.pump();
    await _chooseTool(tester, 'select');
    await marquee(const Offset(250, 350));
    expect(models.map((model) => model.selected), [true, false]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await marquee(const Offset(500, 350));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(models.map((model) => model.selected), [false, true]);
    expect(_selectEnabled(tester), isTrue);
    expect(_canvas(tester).offset, Offset.zero);
  });

  for (final (tool, type) in [('draw', PenStroke), ('arrow', Arrow), ('shape', Shape)]) {
    testWidgets('$tool draws with one finger and discards on navigation takeover', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document()));
      await _chooseTool(tester, tool);
      final controller = _canvas(tester);
      final first = await tester.startGesture(const Offset(200, 300), pointer: 1);
      await first.moveBy(const Offset(60, 30));
      expect(controller.offset, Offset.zero);
      expect(controller.scale, 1);
      final second = await tester.startGesture(const Offset(500, 300), pointer: 2);
      await second.moveBy(const Offset(80, 30));
      expect(controller.scale, greaterThan(1));
      expect(controller.offset, isNot(Offset.zero));
      await second.up();
      final frozen = (controller.offset, controller.scale);
      await first.moveBy(const Offset(60, 30));
      expect((controller.offset, controller.scale), frozen);
      await first.up();
      await tester.pump();
      expect(find.byType(type), findsNothing);

      await tester.dragFrom(const Offset(200, 300), const Offset(120, 90));
      await tester.pump();
      expect(find.byType(type), findsOneWidget);
    });
  }

  for (final (tool, type) in [('text', TextTool), ('code', CodeTool), ('media', MediaTool)]) {
    testWidgets('$tool touch placement waits for release and cancels for pinch', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document()));
      await _chooseTool(tester, tool);
      final first = await tester.startGesture(const Offset(200, 300), pointer: 1);
      expect(find.byType(type), findsNothing);
      final second = await tester.startGesture(const Offset(500, 300), pointer: 2);
      await second.moveBy(const Offset(50, 20));
      await second.up();
      await first.up();
      await tester.pump();
      expect(find.byType(type), findsNothing);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(60, 30));
      await drag.up();
      await tester.pump();
      expect(find.byType(type), findsNothing);
      final canceled = await tester.startGesture(const Offset(200, 300));
      await canceled.cancel();
      await tester.pump();
      expect(find.byType(type), findsNothing);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      expect(find.byType(type), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
    });
  }

  testWidgets('two actual fingers discard a stylus stroke until interrupted pointers release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await _chooseTool(tester, 'draw');
    final controller = _canvas(tester);
    final stylus = await tester.startGesture(const Offset(200, 300), pointer: 1, kind: PointerDeviceKind.stylus);
    final finger = await tester.startGesture(const Offset(400, 300), pointer: 2);
    await stylus.moveBy(const Offset(40, 20));
    await finger.moveBy(const Offset(20, 0));
    expect((controller.offset, controller.scale), (Offset.zero, 1));
    final second = await tester.startGesture(const Offset(600, 300), pointer: 3);
    await second.moveBy(const Offset(40, 20));
    expect(controller.scale, greaterThan(1));
    await second.up();
    await finger.cancel();
    await stylus.moveBy(const Offset(30, 20));
    await stylus.up();
    await tester.pump();
    expect(find.byType(PenStroke), findsNothing);
    final canceled = await tester.startGesture(const Offset(200, 300));
    await canceled.moveBy(const Offset(50, 20));
    await canceled.cancel();
    await tester.pump();
    expect(find.byType(PenStroke), findsNothing);
    await tester.dragFrom(const Offset(200, 300), const Offset(120, 90));
    await tester.pump();
    expect(find.byType(PenStroke), findsOneWidget);
  });

  testWidgets('group movement stops on takeover and remains one undo step', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_pen('a'), _pen('b', const Offset(350, 250))])));
    final models = tester.widgetList<PenStroke>(find.byType(PenStroke)).map((stroke) => stroke.model).toList();
    for (final model in models) {
      model.selected = true;
    }
    final before = models.map((model) => model.data.position).toList();
    final first = await tester.startGesture(const Offset(150, 300), pointer: 1);
    await first.moveBy(const Offset(50, 30));
    await first.moveBy(const Offset(30, 20));
    final moved = models.map((model) => model.data.position).toList();
    expect(moved, isNot(before));
    final second = await tester.startGesture(const Offset(550, 400), pointer: 2);
    await first.moveBy(const Offset(30, 20));
    await second.moveBy(const Offset(30, 20));
    expect(models.map((model) => model.data.position).toList(), moved);
    await second.up();
    await first.up();
    await _undo(tester);
    expect(tester.widgetList<PenStroke>(find.byType(PenStroke)).map((stroke) => stroke.model.data.position), before);
  });

  testWidgets('eraser keeps prior deletions and stops erasing during navigation', (tester) async {
    final store = TestLibraryStore(_document([_pen('a'), _pen('b', const Offset(350, 250))]));
    await pumpCanvas(tester, store);
    await _chooseTool(tester, 'erase');
    final first = await tester.startGesture(const Offset(150, 300), pointer: 1);
    await tester.pump();
    expect(find.byType(PenStroke), findsOneWidget);
    final second = await tester.startGesture(const Offset(500, 450), pointer: 2);
    await first.moveTo(const Offset(400, 300));
    await second.up();
    await first.moveTo(const Offset(400, 300));
    await first.up();
    await tester.pump();
    expect(find.byType(PenStroke), findsOneWidget);
    await pumpPastSave(tester);
    expect(store.persisted!.elements.map((element) => element.id), ['b']);
    await _undo(tester);
    expect(find.byType(PenStroke), findsNWidgets(2));
  });

  for (final control in ['code-block-handle', 'code-block-rotate-control', 'code-block-resize-handle']) {
    testWidgets('$control hands off without further object changes', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document([_code()])));
      final model = tester.widget<CodeTool>(find.byType(CodeTool)).model;
      await tester.tapAt(const Offset(220, 300));
      await tester.pumpAndSettle();
      final first = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(control))), pointer: 1);
      await first.moveBy(const Offset(40, 30));
      await tester.pump();
      final edited = (model.data.position, model.size, model.rotation);
      expect(edited, isNot((const Offset(180, 220), const Size(280, 240), 0)));
      final second = await tester.startGesture(const Offset(600, 450), pointer: 2);
      await first.moveBy(const Offset(30, 20));
      await second.moveBy(const Offset(30, 20));
      expect(_canvas(tester).offset, isNot(Offset.zero));
      expect((model.data.position, model.size, model.rotation), edited);
      await second.up();
      await first.moveBy(const Offset(30, 20));
      await first.up();
      expect((model.data.position, model.size, model.rotation), edited);
      FocusManager.instance.primaryFocus?.unfocus();
      await _undo(tester);
      final restored = tester.widget<CodeTool>(find.byType(CodeTool)).model;
      expect(
        (restored.data.position, restored.size, restored.rotation),
        (const Offset(180, 220), const Size(280, 240), 0),
      );
      await tester.pump(const Duration(milliseconds: 150));
    });
  }

  testWidgets('pinch from a code title does not activate on final release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_code()])));
    final model = tester.widget<CodeTool>(find.byType(CodeTool)).model;
    final title = find.text('title');
    final first = await tester.startGesture(tester.getCenter(title), pointer: 1);
    final second = await tester.startGesture(const Offset(600, 450), pointer: 2);
    // No pump between takeover and release: guards must work synchronously.
    await second.up();
    await first.up();
    await tester.pump();
    expect(model.active, isFalse);
    expect(model.focusNode.hasFocus, isFalse);
    await tester.tapAt(tester.getCenter(title));
    await tester.pump();
    expect(model.active, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('arrow point editing freezes while its pointers navigate', (tester) async {
    await pumpCanvas(
      tester,
      TestLibraryStore(
        _document([
          ArrowElementData(
            id: 'arrow',
            start: const Offset(200, 300),
            controls: const [Offset(350, 300)],
            end: const Offset(500, 300),
            color: const Color(0xff000000),
            strokeStyle: ArrowStrokeStyle.solid,
            strokeWidth: 3,
          ),
        ]),
      ),
    );
    final model = tester.widget<Arrow>(find.byType(Arrow)).model;
    await tester.tapAt(const Offset(350, 300));
    await tester.pumpAndSettle();
    final first = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('arrow-end-handle'))),
      pointer: 1,
    );
    await first.moveBy(const Offset(40, 30));
    final edited = model.data.end;
    expect(edited, isNot(const Offset(500, 300)));
    final second = await tester.startGesture(const Offset(600, 450), pointer: 2);
    await first.moveBy(const Offset(30, 20));
    await second.moveBy(const Offset(30, 20));
    expect(_canvas(tester).offset, isNot(Offset.zero));
    expect(model.data.end, edited);
    await second.up();
    await first.up();
    await _undo(tester);
    expect(tester.widget<Arrow>(find.byType(Arrow)).model.data.end, const Offset(500, 300));
  });
}

// ---------- Helpers and fixtures ----------

LazyCanvasController _canvas(WidgetTester tester) => tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;

bool _selectEnabled(WidgetTester tester) =>
    tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-select'))).selected;

Future<void> _chooseTool(WidgetTester tester, String tool) async {
  await tester.tap(find.byKey(ValueKey('toolbar-$tool')));
  await tester.pump();
}

Future<void> _undo(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

CanvasDocument _document([List<CanvasElementData> elements = const []]) =>
    CanvasDocument(background: CanvasBackgroundKind.plain, elements: elements);

PenElementData _pen(String id, [Offset position = const Offset(100, 250)]) => PenElementData(
  id: id,
  position: position,
  size: const Size(100, 100),
  hitSlop: 6,
  color: const Color(0xff000000),
  width: 3,
  points: const [PenPointData(Offset(0, 50), pressure: 0.5), PenPointData(Offset(100, 50), pressure: 0.5)],
);

CodeElementData _code() => CodeElementData(
  id: 'code',
  position: const Offset(180, 220),
  size: const Size(280, 240),
  language: CodeLanguage.dart,
  source: 'value',
  title: 'title',
  showLineNumbers: true,
);
