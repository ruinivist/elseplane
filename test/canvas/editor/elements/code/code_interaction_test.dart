// Verifies code placement, native editing, and transform controls.

import 'dart:math' as math;

import 'package:elseplane/app/app.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/ui/common/labeled_switch.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../../../test_helpers.dart';

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    final preferences = SharedPreferencesAsync();
    await preferences.remove(PreferencesLibraryStore.libraryKey);
  });

  test('code source edits update durable data', () {
    final model = testCodeModel(
      CodeElementData(
        id: 'code',
        position: Offset.zero,
        size: const Size(280, 240),
        language: CodeLanguage.dart,
        source: '',
        title: '',
        showLineNumbers: true,
      ),
    );

    model.controller.text = 'void main() {}';

    expect(model.data.source, 'void main() {}');
    model.moveBy(const Offset(4, 6));
    expect(model.data.position, const Offset(4, 6));
    model.dispose();
  });

  testWidgets('code places once, returns to select, and focuses editor', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-code')));
    await tester.pump();
    expect(find.byType(CodeElementView), findsNothing);

    await tester.tapAt(const Offset(120, 200));
    await tester.pump();
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    expect(tester.getTopLeft(find.byKey(const ValueKey('code-block-surface'))), const Offset(120, 200));
    expect(code.active, isTrue);
    expect(code.focusNode.hasFocus, isTrue);

    code.controller
      ..text = 'final answer = 42;'
      ..selectAll();
    expect(code.controller.selection.isCollapsed, isFalse);
    code.setSelected(value: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(CodeElementView), findsOneWidget);
    expect(code.active, isFalse);
    expect(code.focusNode.hasFocus, isFalse);
    expect(code.controller.selection.isCollapsed, isTrue);
    expect(code.selected, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('code controls follow editing and persisted display settings', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump();

    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    expect(find.byKey(const ValueKey('code-title-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-language-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-block-resize-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-line-numbers')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-show-line-numbers')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-block-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-block-rotate-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-block-delete-control')), findsOneWidget);
    final codeArea = tester.getRect(
      find.byKey(const ValueKey('code-block-surface')),
    );
    final languagePicker = tester.getRect(
      find.byKey(const ValueKey('code-language-picker')),
    );
    expect(codeArea.contains(languagePicker.topLeft), isTrue);
    expect(codeArea.contains(languagePicker.bottomRight), isTrue);
    expect(
      tester
          .getBottomLeft(
            find.byKey(const ValueKey('code-title-input-tab')),
          )
          .dy,
      codeArea.top,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('code-title-tab')), findsNothing);
    expect(find.byKey(const ValueKey('code-title-input')), findsNothing);
    expect(find.byKey(const ValueKey('code-language-picker')), findsNothing);
    expect(find.byKey(const ValueKey('code-line-numbers')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('code-block-surface'))),
      codeArea,
    );

    await tester.tap(find.byKey(const ValueKey('code-block-preview-surface')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('code-title-input')),
      'main.dart',
    );
    tester
        .widget<TextButton>(
          find.descendant(
            of: find.byKey(const ValueKey('code-show-line-numbers')),
            matching: find.byType(TextButton),
          ),
        )
        .onPressed!();
    await tester.pump();
    expect(code.title, 'main.dart');
    expect(code.showLineNumbers, isFalse);
    expect(
      tester.widget<LabeledSwitch>(find.byKey(const ValueKey('code-show-line-numbers'))).value,
      isFalse,
    );
    expect(find.byKey(const ValueKey('code-line-numbers')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('code-title-input')), findsNothing);
    await tester.pumpAndSettle();
    expect(code.active, isFalse);
    expect(find.byKey(const ValueKey('code-title-tab')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-title-input')), findsNothing);
    expect(find.byKey(const ValueKey('code-language-picker')), findsNothing);
    expect(find.byKey(const ValueKey('code-block-resize-handle')), findsNothing);
    expect(find.byKey(const ValueKey('code-show-line-numbers')), findsNothing);
    expect(find.byKey(const ValueKey('code-block-handle')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('code-block-preview-surface')));
    await tester.pump();
    expect(code.active, isTrue);
    expect(find.byKey(const ValueKey('code-title-tab')), findsNothing);
    expect(find.byKey(const ValueKey('code-title-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-line-numbers')), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('code-block-delete-control')));
    await tester.pumpAndSettle();
    expect(find.byType(CodeElementView), findsNothing);
    expect(find.byType(ElementTransformControls), findsNothing);
  });

  testWidgets('active code blocks move and rotate from floating controls', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump();

    final block = find.byType(CodeElementView);
    final model = tester.widget<CodeElementView>(block).resources;
    final originalPosition = model.data.position;
    const moveDelta = Offset(80, 60);

    await tester.drag(
      find.byKey(const ValueKey('code-block-handle')),
      moveDelta,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(model.data.position, originalPosition + moveDelta);
    expect(model.active, isTrue);
    expect(find.byKey(const ValueKey('code-title-input')), findsOneWidget);

    final rotate = find.byKey(const ValueKey('code-block-rotate-control'));
    final center = tester.getCenter(find.byKey(const ValueKey('code-block-surface')));
    final start = tester.getCenter(rotate);
    final radius = (start - center).distance;
    final startAngle = math.atan2(start.dy - center.dy, start.dx - center.dx);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(
      center + Offset.fromDirection(startAngle + math.pi / 2, radius),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(model.rotation.abs(), closeTo(math.pi / 2, 0.01));
    expect(model.active, isTrue);
    expect(find.byKey(const ValueKey('code-title-input')), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('code title grows and drags in screen coordinates under rotation and zoom', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump();

    final input = find.byKey(const ValueKey('code-title-input'));
    final tab = find.byKey(const ValueKey('code-title-input-tab'));
    final surface = find.byKey(const ValueKey('code-block-surface'));

    await tester.tap(input);
    await tester.enterText(input, 'main.dart');
    await tester.pumpAndSettle();

    final shortWidth = tester.getSize(tab).width;

    await tester.enterText(input, 'a' * 100);
    await tester.pumpAndSettle();

    expect(tester.getSize(tab).width, greaterThan(shortWidth));
    expect(tester.getSize(tab).width, tester.getSize(surface).width);
    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources..rotate(math.pi / 2);
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
      ..updateScalebyDelta(-0.5, focalPoint: Offset.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final before = model.canvasPosition;
    final order = controller.childOrder;
    await tester.drag(
      find.byKey(const ValueKey('code-title-tab')),
      const Offset(30, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.canvasPosition, before + const Offset(60, 40));
    expect(controller.getInfo(model.data.id).gsPosition, model.canvasPosition);
    expect(model.active, isFalse);
    expect(controller.childOrder, order);
  });

  testWidgets('delete removes an active unselected code block', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await placeCodeBlock(tester, const Offset(120, 140));

    final block = find.byType(CodeElementView);
    final code = tester.widget<CodeElementView>(block).resources;
    code.focusNode.unfocus();
    await tester.pump();

    expect(code.active, isTrue);
    expect(code.selected, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(block, findsNothing);
  });

  testWidgets('code blocks resize from the bottom-right handle', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await placeCodeBlock(tester, const Offset(40, 120));
    await tester.pump(const Duration(milliseconds: 100));

    final block = find.byType(CodeElementView);
    final model = tester.widget<CodeElementView>(block).resources;
    final handle = find.byKey(const ValueKey('code-block-resize-handle'));
    final originalSize = tester.getSize(block);

    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(80, 60));
    await tester.pump();

    final enlargedSize = tester.getSize(block);
    expect(enlargedSize.width, greaterThan(originalSize.width));
    expect(enlargedSize.height, greaterThan(originalSize.height));

    await tester.drag(handle, const Offset(-1000, -1000));
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('code-block-surface'))),
      codeBlockMinimumSize,
    );

    final clampedSize = model.size;
    model.rotate(-math.pi / 4);
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
      ..updateScalebyDelta(-0.25, focalPoint: Offset.zero);
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('code-block-resize-handle')),
      Offset.fromDirection(-math.pi / 4, 80 * controller.scale),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(model.size.width, closeTo(clampedSize.width + 80, 0.01));
    expect(model.size.height, closeTo(clampedSize.height, 0.01));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('code scroll boundary does not pan canvas', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await placeCodeBlock(tester, const Offset(120, 140));

    final block = find.byType(CodeElementView);
    final model = tester.widget<CodeElementView>(block).resources;
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    model.controller.text = List.generate(
      100,
      (index) => 'line $index',
    ).join('\n');
    await tester.pump();
    expect(
      model.scrollController.verticalScroller.position.maxScrollExtent,
      greaterThan(0),
    );

    model.scrollController.verticalScroller.jumpTo(
      model.scrollController.verticalScroller.position.maxScrollExtent,
    );
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(block)),
    );
    await tester.sendEventToBinding(
      pointer.scroll(const Offset(0, 20)),
    );
    await tester.pump();

    expect(canvas.controller.offset, Offset.zero);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('inactive code blocks move from the surface without selecting', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await placeCodeBlock(tester, const Offset(120, 140));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final block = find.byType(CodeElementView);
    final model = tester.widget<CodeElementView>(block).resources;
    final originalPosition = model.data.position;
    final preview = find.byKey(const ValueKey('code-block-preview-surface'));

    expect(tester.widget<CodeElementView>(block).resources.selected, isFalse);

    const delta = Offset(80, 60);
    await tester.drag(preview, delta);
    await tester.pump();

    expect(model.data.position, originalPosition + delta);

    await tester.tapAt(const Offset(24, 200));
    await tester.pump();
    expect(tester.widget<CodeElementView>(block).resources.selected, isFalse);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  });

  testWidgets('code editor keeps native select and delete actions', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();
    await placeCodeBlock(tester, const Offset(300, 200));
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources..setSelected(value: true);
    code.controller.text = 'native code';
    code.focusNode.requestFocus();
    await tester.pump();
    code.controller.selectAll();
    await tester.pump();
    expect(code.controller.isAllSelected, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(find.byType(CodeElementView), findsOneWidget);
    expect(code.selected, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
