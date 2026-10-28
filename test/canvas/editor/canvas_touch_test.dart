// Verifies touch ownership between canvas tools, object edits, and navigation.
// Exercises elseplane's handoff through real pointer sequences and persisted models.

import 'dart:async';
import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_preview.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;

import '../test_helpers.dart';
import '../touch_test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  for (final frameHz in [60, 120]) {
    for (final objectJump in [false, true]) {
      testWidgets('handoff checks reject restored ${objectJump ? 'object' : 'viewport'} jumps at $frameHz Hz', (
        tester,
      ) async {
        await pumpCanvas(tester, TestLibraryStore(touchDocument([_code()])));
        final controller = _canvas(tester);
        final start = touchView(controller);
        final object = find.byType(CodeElementView);
        final model = tester.widget<CodeElementView>(object).resources;
        final original = model.data;
        final corners = touchWorldCorners(tester, object, start);
        if (objectJump) {
          model.moveBy(const Offset(0, 20));
        } else {
          controller.scrollBy(const Offset(0, 20));
        }
        tester.binding.addPostFrameCallback((_) {
          if (objectJump) {
            model.moveBy(const Offset(0, -20));
          } else {
            controller.scrollBy(const Offset(0, -20));
          }
        });
        tester.binding.scheduleFrame();
        TestFailure? failure;
        try {
          await pumpTouchResponse(
            tester,
            previous: start,
            target: start,
            frameHz: frameHz,
            onFrame: (view) {
              expect(model.data, original);
              expectTouchWorldCorners(tester, object, corners, view);
            },
          );
        } on TestFailure catch (error) {
          failure = error;
        }
        expect(failure, isA<TestFailure>());
        expect(model.data, original);
        expectTouchWorldCorners(tester, object, corners, start);
        TouchMotionReport()
          ..sample(Duration.zero, paintedTouchLandmarks(tester), start, 'restored endpoint')
          ..verify();
      });
    }
    for (final canceled in [false, true]) {
      for (final corrupt in [false, true]) {
        testWidgets(
          '${canceled ? 'canceled' : 'held'} touch ${corrupt ? 'rejects restored drift' : 'stays stable'} over 200ms at $frameHz Hz',
          (tester) async {
            await pumpCanvas(tester, TestLibraryStore(touchDocument()));
            final controller = _canvas(tester);
            final start = touchView(controller);
            final first = await tester.startGesture(const Offset(250, 340), pointer: 1);
            final second = await tester.startGesture(const Offset(490, 340), pointer: 2);
            const delta = Offset(20, 10);
            await first.moveBy(delta);
            await second.moveBy(delta);
            final frozen = (offset: start.offset - delta / start.scale, scale: start.scale);
            await pumpTouchResponse(tester, previous: start, target: frozen, frameHz: frameHz);
            if (canceled) {
              await first.cancel();
              await second.cancel();
            }
            if (corrupt) {
              Timer(const Duration(milliseconds: 40), () => controller.scrollBy(const Offset(0, 20)));
              Timer(const Duration(milliseconds: 140), () => controller.scrollBy(const Offset(0, -20)));
            }
            TestFailure? failure;
            try {
              await pumpTouchHold(tester, expected: frozen, frameHz: frameHz);
            } on TestFailure catch (error) {
              failure = error;
            }
            if (corrupt) {
              expect(failure, isA<TestFailure>());
              final observed = RegExp(r'at (\d+)us').firstMatch(failure?.message ?? '');
              expect(observed, isNotNull);
              expect(int.parse(observed!.group(1)!), inInclusiveRange(40000, 140000));
            } else {
              expect(failure, isNull);
            }
            TouchMotionReport()
              ..sample(Duration.zero, paintedTouchLandmarks(tester), frozen, 'restored endpoint')
              ..verify();
            if (!canceled) {
              await first.up();
              await second.up();
            }
          },
        );
      }
    }
  }

  testWidgets('empty touch pans after slop, preserves selection, and converts zoom', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_pen('a')])));
    final model = tester.widget<PenElementView>(find.byType(PenElementView)).resources..setSelected(value: true);
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
    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    await tester.tapAt(const Offset(220, 300));
    await tester.pumpAndSettle();
    model.setSelected(value: true);
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
      await pumpCanvas(tester, TestLibraryStore(touchDocument([_pen('a')])));
      final model = tester.widget<PenElementView>(find.byType(PenElementView)).resources..setSelected(value: true);
      final controller = _canvas(tester);
      final touch = await tester.startGesture(const Offset(550, 400));
      await touch.moveBy(displacement, timeStamp: const Duration(milliseconds: 16));
      await touch.moveBy(displacement, timeStamp: const Duration(milliseconds: 32));
      final frozenView = touchView(controller);
      final frozen = frozenView.offset;
      await touch.cancel();
      await pumpTouchHold(tester, expected: frozenView, onFrame: (_) => expect(model.selected, isTrue));
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
      await pumpCanvas(tester, TestLibraryStore(touchDocument([_pen('a')])));
      final model = tester.widget<PenElementView>(find.byType(PenElementView)).resources..setSelected(value: true);
      final controller = _canvas(tester);
      final first = await tester.startGesture(const Offset(200, 400), pointer: 1);
      await first.moveBy(displacement, timeStamp: const Duration(milliseconds: 16));
      final beforeNavigation = touchView(controller);
      final panned = (controller.offset, controller.scale);
      final second = await tester.startGesture(const Offset(550, 400), pointer: 2);
      expect((controller.offset, controller.scale), panned);
      const delta = Offset(60, 30);
      final target = _stationaryTarget(tester, beforeNavigation, (
        const Offset(200, 400) + displacement,
        const Offset(550, 400),
      ), delta);
      await second.moveBy(delta);
      await pumpTouchResponse(
        tester,
        previous: beforeNavigation,
        target: target,
        onFrame: (_) => expect(model.selected, isTrue),
      );
      expect((controller.offset, controller.scale), isNot(panned));
      final frozenView = target;
      await second.up();
      final frozen = (frozenView.offset, frozenView.scale);
      await first.moveBy(const Offset(60, 30));
      await first.up();
      await pumpTouchHold(tester, expected: frozenView, onFrame: (_) => expect(model.selected, isTrue));
      expect((controller.offset, controller.scale), frozen);
      expect(model.selected, isTrue);
      final fresh = await tester.startGesture(const Offset(550, 400));
      await fresh.moveBy(const Offset(40, 20));
      expect(controller.offset, frozen.$1 - const Offset(40, 20) / controller.scale);
      await fresh.cancel();
    });
  }

  testWidgets('tool changes cancel empty touch pan through final release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(touchDocument()));
    final controller = _canvas(tester);
    final touch = await tester.startGesture(const Offset(200, 300));
    await touch.moveBy(const Offset(60, 30));
    final frozenView = touchView(controller);
    final frozen = frozenView.offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await touch.moveBy(const Offset(60, 30));
    await touch.up();
    await pumpTouchHold(
      tester,
      expected: frozenView,
      onFrame: (_) {
        _expectNoDrafts(tester);
        expect(find.byType(PenElementView), findsNothing);
      },
    );
    expect(controller.offset, frozen);
    expect(find.byType(PenElementView), findsNothing);
  });

  testWidgets('document replacement cancels an empty touch pan', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(touchDocument([_pen('a')])));
    await tester.dragFrom(const Offset(150, 300), const Offset(60, 30));
    await tester.pump();
    final controller = _canvas(tester);
    final touch = await tester.startGesture(const Offset(550, 400));
    await touch.moveBy(const Offset(60, 30));
    final frozenView = touchView(controller);
    final frozen = frozenView.offset;
    await _undo(tester);
    await touch.moveBy(const Offset(60, 30));
    await touch.up();
    await pumpTouchHold(
      tester,
      expected: frozenView,
      onFrame: (_) {
        expect(
          tester.widget<PenElementView>(find.byType(PenElementView)).resources.data.position,
          const Offset(100, 250),
        );
      },
    );
    expect(controller.offset, frozen);
    expect(tester.widget<PenElementView>(find.byType(PenElementView)).resources.data.position, const Offset(100, 250));
  });

  for (final select in [false, true]) {
    testWidgets('touch object movement with Select $select leaves the viewport fixed', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document([_pen('a')])), platform: TargetPlatform.android);
      if (select) await _chooseTool(tester, 'select');
      final model = tester.widget<PenElementView>(find.byType(PenElementView)).resources;
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
    final models = tester
        .widgetList<PenElementView>(find.byType(PenElementView))
        .map((stroke) => stroke.resources)
        .toList();
    models[1].setSelected(value: true);
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
    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    await tester.tapAt(const Offset(220, 300));
    await tester.pumpAndSettle();
    model.setSelected(value: true);
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
      final models = tester
          .widgetList<PenElementView>(find.byType(PenElementView))
          .map((stroke) => stroke.resources)
          .toList();
      models[1].setSelected(value: true);
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
    expect(find.byType(PenElementView), findsNothing);
    expect(_selectEnabled(tester), isTrue);
    await _chooseTool(tester, 'shape');
    expect(_selectEnabled(tester), isFalse);
    await tester.dragFrom(const Offset(200, 300), const Offset(80, 60));
    await tester.pump();
    expect(find.byType(ShapeElementView), findsOneWidget);
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
      final models = tester
          .widgetList<PenElementView>(find.byType(PenElementView))
          .map((stroke) => stroke.resources)
          .toList();
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
    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    expect(model.active, isTrue);
    model.setSelected(value: true);
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
      tester.widget<PenElementView>(find.byType(PenElementView)).resources.data.position,
      canvasElement(tester, tester.widget<ShapeElementView>(find.byType(ShapeElementView)).data).data.position,
      canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data).data.start,
    ];
    final before = positions();
    for (final select in [false, true]) {
      if (select) await _chooseTool(tester, 'select');
      tester.widget<PenElementView>(find.byType(PenElementView)).resources.setSelected(value: true);
      canvasElement(
        tester,
        tester.widget<ShapeElementView>(find.byType(ShapeElementView)).data,
      ).setSelected(value: true);
      canvasElement(
        tester,
        tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data,
      ).setSelected(value: true);
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

  testWidgets('touch marquee overlaps rotated bounds after pan and non-default zoom', (tester) async {
    final code = _code().copyWith(position: const Offset(160, 140), rotation: math.pi / 2, title: '');
    await pumpCanvas(tester, TestLibraryStore(_document([code])), platform: TargetPlatform.android);
    await _chooseTool(tester, 'select');
    const panDelta = Offset(-80, 60);
    final controller = _canvas(tester)
      ..updateScalebyDelta(0.5, focalPoint: Offset.zero)
      ..onScaleStart(ScaleStartDetails())
      ..onScaleUpdate(ScaleUpdateDetails(focalPointDelta: panDelta));
    await tester.pump();
    final before = controller.offset;
    // This box hits the rotated top edge, above the unrotated screen bounds.
    final touch = await tester.startGesture(const Offset(415, 175) + panDelta);
    await touch.moveTo(const Offset(475, 205) + panDelta);
    await touch.up();
    await tester.pump();
    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
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
    final models = tester
        .widgetList<PenElementView>(find.byType(PenElementView))
        .map((stroke) => stroke.resources)
        .toList();
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

  for (final (tool, type) in [('draw', PenElementView), ('arrow', ArrowElementView), ('shape', ShapeElementView)]) {
    testWidgets('$tool draws with one finger and discards on navigation takeover', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(touchDocument()));
      await _chooseTool(tester, tool);
      final controller = _canvas(tester);
      final first = await tester.startGesture(const Offset(200, 300), pointer: 1);
      await first.moveBy(const Offset(60, 30));
      expect(controller.offset, Offset.zero);
      expect(controller.scale, 1);
      final beforeNavigation = touchView(controller);
      final second = await tester.startGesture(const Offset(500, 300), pointer: 2);
      const delta = Offset(80, 30);
      final target = _stationaryTarget(tester, beforeNavigation, (
        const Offset(260, 330),
        const Offset(500, 300),
      ), delta);
      await second.moveBy(delta);
      await pumpTouchResponse(
        tester,
        previous: beforeNavigation,
        target: target,
        onFrame: (_) {
          _expectNoDrafts(tester);
          expect(_toolViews(type), findsNothing);
        },
      );
      expect(controller.scale, greaterThan(1));
      expect(controller.offset, isNot(Offset.zero));
      await second.up();
      final frozen = (controller.offset, controller.scale);
      await first.moveBy(const Offset(60, 30));
      expect((controller.offset, controller.scale), frozen);
      await first.up();
      await tester.pump();
      expect(_toolViews(type), findsNothing);

      await tester.dragFrom(const Offset(200, 300), const Offset(120, 90));
      await tester.pump();
      expect(_toolViews(type), findsOneWidget);
    });
  }

  for (final (tool, type) in [('text', TextElementView), ('code', CodeElementView), ('media', MediaElementView)]) {
    testWidgets('$tool touch placement waits for release and cancels for pinch', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document()));
      await _chooseTool(tester, tool);
      final first = await tester.startGesture(const Offset(200, 300), pointer: 1);
      expect(_toolViews(type), findsNothing);
      final second = await tester.startGesture(const Offset(500, 300), pointer: 2);
      await second.moveBy(const Offset(50, 20));
      await second.up();
      await first.up();
      await tester.pump();
      expect(_toolViews(type), findsNothing);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(60, 30));
      await drag.up();
      await tester.pump();
      expect(_toolViews(type), findsNothing);
      final canceled = await tester.startGesture(const Offset(200, 300));
      await canceled.cancel();
      await tester.pump();
      expect(_toolViews(type), findsNothing);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      expect(_toolViews(type), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
    });
  }

  testWidgets('two actual fingers discard a stylus stroke until interrupted pointers release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(touchDocument()));
    await _chooseTool(tester, 'draw');
    final controller = _canvas(tester);
    final stylus = await tester.startGesture(const Offset(200, 300), pointer: 1, kind: PointerDeviceKind.stylus);
    final finger = await tester.startGesture(const Offset(400, 300), pointer: 2);
    await stylus.moveBy(const Offset(40, 20));
    await finger.moveBy(const Offset(20, 0));
    expect((controller.offset, controller.scale), (Offset.zero, 1));
    final beforeNavigation = touchView(controller);
    final second = await tester.startGesture(const Offset(600, 300), pointer: 3);
    const delta = Offset(40, 20);
    final target = _stationaryTarget(tester, beforeNavigation, (const Offset(420, 300), const Offset(600, 300)), delta);
    await second.moveBy(delta);
    await pumpTouchResponse(
      tester,
      previous: beforeNavigation,
      target: target,
      onFrame: (_) {
        _expectNoDrafts(tester);
        expect(find.byType(PenElementView), findsNothing);
      },
    );
    expect(controller.scale, greaterThan(1));
    await second.up();
    await finger.cancel();
    await stylus.moveBy(const Offset(30, 20));
    await stylus.up();
    await tester.pump();
    expect(find.byType(PenElementView), findsNothing);
    final canceled = await tester.startGesture(const Offset(200, 300));
    await canceled.moveBy(const Offset(50, 20));
    await canceled.cancel();
    await tester.pump();
    expect(find.byType(PenElementView), findsNothing);
    await tester.dragFrom(const Offset(200, 300), const Offset(120, 90));
    await tester.pump();
    expect(find.byType(PenElementView), findsOneWidget);
  });

  testWidgets('group movement stops on takeover and remains one undo step', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_pen('a'), _pen('b', const Offset(350, 250))])));
    final models = tester
        .widgetList<PenElementView>(find.byType(PenElementView))
        .map((stroke) => stroke.resources)
        .toList();
    for (final model in models) {
      model.setSelected(value: true);
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
    expect(
      tester.widgetList<PenElementView>(find.byType(PenElementView)).map((stroke) => stroke.resources.data.position),
      before,
    );
  });

  testWidgets('eraser keeps prior deletions and stops erasing during navigation', (tester) async {
    final store = TestLibraryStore(_document([_pen('a'), _pen('b', const Offset(350, 250))]));
    await pumpCanvas(tester, store);
    await _chooseTool(tester, 'erase');
    final first = await tester.startGesture(const Offset(150, 300), pointer: 1);
    await tester.pump();
    expect(find.byType(PenElementView), findsOneWidget);
    final second = await tester.startGesture(const Offset(500, 450), pointer: 2);
    await first.moveTo(const Offset(400, 300));
    await second.up();
    await first.moveTo(const Offset(400, 300));
    await first.up();
    await tester.pump();
    expect(find.byType(PenElementView), findsOneWidget);
    await pumpPastSave(tester);
    expect(store.persisted!.elements.map((element) => element.id), ['b']);
    await _undo(tester);
    expect(find.byType(PenElementView), findsNWidgets(2));
  });

  for (final control in ['code-block-handle', 'code-block-rotate-control', 'code-block-resize-handle']) {
    testWidgets('$control hands off without further object changes', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(touchDocument([_code()])));
      final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
      await tester.tapAt(const Offset(220, 300));
      await tester.pumpAndSettle();
      final first = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(control))), pointer: 1);
      await first.moveBy(const Offset(40, 30));
      await tester.pump();
      final edited = (model.data.position, model.size, model.rotation);
      expect(edited, isNot((const Offset(180, 220), const Size(280, 240), 0)));
      final beforeNavigation = touchView(_canvas(tester));
      final object = find.byType(CodeElementView);
      final corners = touchWorldCorners(tester, object, beforeNavigation);
      final second = await tester.startGesture(const Offset(600, 450), pointer: 2);
      expect((model.data.position, model.size, model.rotation), edited);
      const delta = Offset(30, 20);
      await first.moveBy(delta);
      expect((model.data.position, model.size, model.rotation), edited);
      await second.moveBy(delta);
      final target = (offset: beforeNavigation.offset - delta / beforeNavigation.scale, scale: beforeNavigation.scale);
      await pumpTouchResponse(
        tester,
        previous: beforeNavigation,
        target: target,
        onFrame: (view) {
          expect((model.data.position, model.size, model.rotation), edited);
          expectTouchWorldCorners(tester, object, corners, view);
        },
      );
      expect(_canvas(tester).offset, isNot(Offset.zero));
      expect((model.data.position, model.size, model.rotation), edited);
      await second.up();
      await first.moveBy(const Offset(30, 20));
      await first.up();
      expect((model.data.position, model.size, model.rotation), edited);
      FocusManager.instance.primaryFocus?.unfocus();
      await _undo(tester);
      final restored = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
      expect(
        (restored.data.position, restored.size, restored.rotation),
        (const Offset(180, 220), const Size(280, 240), 0),
      );
      await tester.pump(const Duration(milliseconds: 150));
    });
  }

  testWidgets('pinch from a code title does not activate on final release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document([_code()])));
    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
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
        touchDocument([
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
    final model = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
    await tester.tapAt(const Offset(350, 300));
    await tester.pumpAndSettle();
    final first = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('arrow-end-handle'))),
      pointer: 1,
    );
    await first.moveBy(const Offset(40, 30));
    final edited = model.data.end;
    expect(edited, isNot(const Offset(500, 300)));
    await tester.pump();
    final beforeNavigation = touchView(_canvas(tester));
    final object = find.byType(ArrowElementView);
    final corners = touchWorldCorners(tester, object, beforeNavigation);
    final second = await tester.startGesture(const Offset(600, 450), pointer: 2);
    expect(model.data.end, edited);
    const delta = Offset(30, 20);
    await first.moveBy(delta);
    expect(model.data.end, edited);
    await second.moveBy(delta);
    final target = (offset: beforeNavigation.offset - delta / beforeNavigation.scale, scale: beforeNavigation.scale);
    await pumpTouchResponse(
      tester,
      previous: beforeNavigation,
      target: target,
      onFrame: (view) {
        expect(model.data.end, edited);
        expectTouchWorldCorners(tester, object, corners, view);
      },
    );
    expect(_canvas(tester).offset, isNot(Offset.zero));
    expect(model.data.end, edited);
    await second.up();
    await first.up();
    await _undo(tester);
    expect(
      canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data).data.end,
      const Offset(500, 300),
    );
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

// Fixture landmarks are not content produced by drawing tools.
Finder _toolViews(Type type) => find.byWidgetPredicate(
  (widget) => widget.runtimeType == type && (widget is! ShapeElementView || !widget.data.id.startsWith('landmark-')),
);

TouchView _stationaryTarget(WidgetTester tester, TouchView start, TouchTouches initial, Offset delta) {
  final origin = tester.getTopLeft(find.byType(LazyCanvas));
  final local = (initial.$1 - origin, initial.$2 - origin);
  final raw = stationaryTouchView(start, local, (local.$1, local.$2 + delta));
  final controller = _canvas(tester);
  final scale = raw.scale.clamp(controller.minScale!, controller.maxScale!);
  return (offset: start.offset + local.$1 / start.scale - local.$1 / scale, scale: scale);
}

void _expectNoDrafts(WidgetTester tester) {
  expect(find.byKey(const ValueKey('arrow-preview')), findsNothing);
  expect(find.byKey(const ValueKey('shape-preview')), findsNothing);
  final pen = find.byKey(const ValueKey('pen-preview'));
  if (pen.evaluate().isNotEmpty) {
    final tool = (tester.widget<CustomPaint>(pen).painter! as PenPreviewPainter).tool;
    expect(tool.active, isFalse);
    expect(tool.points, isEmpty);
  }
}
