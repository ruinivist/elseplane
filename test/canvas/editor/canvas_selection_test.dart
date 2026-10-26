// Verifies selection, mixed group movement, and marquee behavior.

import 'dart:math' as math;

import 'package:elseplane/app/app.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    final preferences = SharedPreferencesAsync();
    await preferences.remove(PreferencesLibraryStore.libraryKey);
  });

  testWidgets('primary+A selects and deletes offscreen mixed children', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(40, 520));
    await tester.pump();
    await tester.pump();
    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    text.moveBy(const Offset(10000, 10000) - text.canvasPosition);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.dragFrom(
      const Offset(350, 540),
      const Offset(50, 20),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump(const Duration(milliseconds: 100));

    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    final stroke = tester.widget<PenElementView>(find.byType(PenElementView)).resources;
    final visibleIds = canvas.controller.widgetsWithScreenPositions().map((child) => child.id).toList();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(text.selected, isTrue);
    expect(code.selected, isTrue);
    expect(stroke.selected, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await tester.pump();

    expect(find.byType(TextElementView), findsNothing);
    expect(find.byType(CodeElementView), findsNothing);
    expect(find.byType(PenElementView), findsNothing);
    expect(canvas.controller.hasChild(text.data.id), isFalse);
    for (final id in visibleIds) {
      expect(canvas.controller.hasChild(id), isFalse);
    }
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    final savedNodes = (await PreferencesLibraryStore().load())!.current.document!.elements;
    expect(savedNodes, hasLength(0));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await tester.pump();
  });

  testWidgets('ctrl-click multi-selects without activating blocks', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(40, 350));
    await tester.pump();
    await tester.pump();
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump(const Duration(milliseconds: 100));

    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    final textTapPosition =
        tester.getTopLeft(
          find.byKey(const ValueKey('text-markdown-preview-surface')),
        ) +
        const Offset(32, 32);
    final codeSurfaceCenter = tester.getCenter(
      find.byKey(const ValueKey('code-block-surface')),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(code.active, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(textTapPosition);
    await tester.pump();
    await tester.tapAt(codeSurfaceCenter);
    await tester.pump();
    expect(text.selected, isTrue);
    expect(code.selected, isTrue);
    expect(text.active, isFalse);
    expect(code.active, isTrue);
    await tester.tapAt(codeSurfaceCenter);
    await tester.pump();
    expect(text.selected, isTrue);
    expect(code.selected, isFalse);
    await tester.tapAt(codeSurfaceCenter);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(text.selected, isTrue);
    expect(code.selected, isTrue);
    expect(text.editing, isFalse);
    expect(text.focusNode.hasFocus, isFalse);
    expect(code.focusNode.hasFocus, isFalse);
    final selectedSemantics = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(
      find.descendant(of: find.byType(TextElementView), matching: selectedSemantics),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(CodeElementView), matching: selectedSemantics),
      findsOneWidget,
    );

    await tester.tapAt(textTapPosition);
    await tester.pump();
    expect(text.active, isTrue);
    expect(code.active, isFalse);
    expect(text.editing, isTrue);
    expect(text.selected, isFalse);
    expect(code.selected, isFalse);

    await tester.tapAt(const Offset(20, 300));
    await tester.pump();
    expect(text.selected, isFalse);
    expect(code.selected, isFalse);
  });

  testWidgets('dragging a selected mixed group moves once under zoom', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(40, 520));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.dragFrom(
      const Offset(350, 540),
      const Offset(50, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump(const Duration(milliseconds: 100));

    final textFinder = find.byType(TextElementView);
    final codeFinder = find.byType(CodeElementView);
    final strokeFinder = find.byType(PenElementView);
    final text = tester.widget<TextElementView>(textFinder).resources;
    final code = tester.widget<CodeElementView>(codeFinder).resources;
    final stroke = tester.widget<PenElementView>(strokeFinder).resources;
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
      ..updateScalebyDelta(-0.5, focalPoint: Offset.zero);
    text.rotate(math.pi / 6);
    await tester.pump();
    final originalPositions = [text.canvasPosition, code.canvasPosition, stroke.canvasPosition];
    final textPosition = tester.getTopLeft(textFinder);
    final codePosition = tester.getTopLeft(codeFinder);
    final strokePosition = tester.getTopLeft(strokeFinder);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey('text-markdown-preview-surface')),
      ),
    );
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('code-block-surface'))),
    );
    await tester.pump();
    await tester.tapAt(tester.getCenter(strokeFinder));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(text.selected, isTrue);
    expect(code.selected, isTrue);
    expect(stroke.selected, isTrue);

    final order = controller.childOrder;
    const delta = Offset(48, 36);
    await tester.drag(strokeFinder, delta, kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(tester.getTopLeft(textFinder), textPosition + delta);
    expect(tester.getTopLeft(codeFinder), codePosition + delta);
    expect(tester.getTopLeft(strokeFinder), strokePosition + delta);
    expect(text.selected, isTrue);
    expect(code.selected, isTrue);
    expect(stroke.selected, isTrue);
    expect(controller.childOrder, order);
    for (var index = 0; index < 3; index++) {
      final model = <ElementResources>[text, code, stroke][index];
      expect(model.canvasPosition, originalPositions[index] + delta / controller.scale);
      expect(controller.getInfo(model.data.id).gsPosition, model.canvasPosition);
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('resizing a selected widget clears the rest of the selection', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(40, 350));
    await tester.pump();
    await tester.pump();
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump(const Duration(milliseconds: 100));

    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(
            find.byKey(const ValueKey('text-markdown-preview-surface')),
          ) +
          const Offset(32, 32),
    );
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('code-block-surface'))),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(text.selected, isTrue);
    expect(code.selected, isTrue);
    final originalSize = code.size;
    await tester.drag(
      find.byKey(const ValueKey('code-block-resize-handle')),
      const Offset(80, 60),
    );
    await tester.pump();

    expect(code.size, isNot(originalSize));
    expect(text.selected, isFalse);
    expect(code.selected, isFalse);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('dragging an unselected child clears selection and moves alone', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(40, 350));
    await tester.pump();
    await tester.pump();
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final textFinder = find.byType(TextElementView);
    final codeFinder = find.byType(CodeElementView);
    final text = tester.widget<TextElementView>(textFinder).resources;
    final code = tester.widget<CodeElementView>(codeFinder).resources;
    final preview = find.byKey(const ValueKey('code-block-preview-surface'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(
            find.byKey(const ValueKey('text-markdown-preview-surface')),
          ) +
          const Offset(32, 32),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(text.selected, isTrue);
    expect(code.selected, isFalse);

    final textPosition = tester.getTopLeft(textFinder);
    final codePosition = tester.getTopLeft(codeFinder);
    const delta = Offset(72, 44);
    await tester.drag(preview, delta, kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(tester.getTopLeft(textFinder), textPosition);
    expect(tester.getTopLeft(codeFinder), codePosition + delta);
    expect(text.selected, isFalse);
    expect(code.selected, isFalse);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('drag marquee selects overlaps and ctrl toggles hits', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(40, 520));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(500, 520));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.dragFrom(
      const Offset(350, 540),
      const Offset(50, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump(const Duration(milliseconds: 100));

    final texts = tester
        .widgetList<TextElementView>(find.byType(TextElementView))
        .map((block) => block.resources)
        .toList();
    final insideText = texts.singleWhere(
      (model) => model.node.position.dx == 40,
    );
    final outsideText = texts.singleWhere(
      (model) => model.node.position.dx == 500,
    );
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    final stroke = tester.widget<PenElementView>(find.byType(PenElementView)).resources;

    final marquee = await tester.startGesture(
      const Offset(20, 590),
      kind: PointerDeviceKind.mouse,
    );
    await marquee.moveTo(const Offset(380, 490));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('drag-selection-marquee')),
      findsOneWidget,
    );
    expect(insideText.selected, isTrue);
    expect(code.selected, isTrue);
    expect(stroke.selected, isTrue);
    expect(outsideText.selected, isFalse);
    expect(insideText.editing, isFalse);
    expect(code.focusNode.hasFocus, isFalse);

    await marquee.up();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('drag-selection-marquee')),
      findsNothing,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(const Offset(640, 546));
    await tester.pump();
    expect(outsideText.selected, isTrue);

    final toggleMarquee = await tester.startGesture(
      const Offset(20, 590),
      kind: PointerDeviceKind.mouse,
    );
    await toggleMarquee.moveTo(const Offset(380, 490));
    await toggleMarquee.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(insideText.selected, isFalse);
    expect(code.selected, isFalse);
    expect(stroke.selected, isFalse);
    expect(outsideText.selected, isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('marquee uses rotated bounds after pointer drag threshold', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await placeCodeBlock(tester, const Offset(200, 200));

    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources
      ..setSize(const Size(400, 200))
      ..rotate(math.pi / 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final tinyDrag = await tester.startGesture(
      const Offset(700, 500),
      kind: PointerDeviceKind.mouse,
    );
    await tinyDrag.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('drag-selection-marquee')), findsNothing);
    await tinyDrag.up();

    final unrotatedCorner = await tester.startGesture(
      const Offset(560, 210),
      kind: PointerDeviceKind.mouse,
    );
    await unrotatedCorner.moveTo(const Offset(590, 240));
    await tester.pump();
    expect(model.selected, isFalse);
    await unrotatedCorner.up();

    final rotatedCorner = await tester.startGesture(
      const Offset(350, 100),
      kind: PointerDeviceKind.mouse,
    );
    await rotatedCorner.moveTo(const Offset(390, 160));
    await tester.pump();
    expect(model.selected, isTrue);
    await rotatedCorner.up();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('deleting code keeps unrelated text editing open', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();
    await placeCodeBlock(tester, const Offset(300, 200));
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources..setSelected(value: true);

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 200));
    await tester.pump();
    await tester.pump();
    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    expect(text.editing, isTrue);
    expect(find.byKey(const ValueKey('text-block-handle')), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CodeElementView), findsNothing);
    expect(find.byType(TextElementView), findsOneWidget);
    expect(text.editing, isTrue);
    expect(find.byKey(const ValueKey('text-block-handle')), findsOneWidget);
    expect(code.session.selectedIds, isNot(contains(code.data.id)));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
