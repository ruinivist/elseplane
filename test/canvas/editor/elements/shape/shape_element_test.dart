// Verifies persisted shape hit targets, options, and controls.

import 'dart:async';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_view.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_editor_resources.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_tool_settings.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/canvas/geometry/shape_geometry.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../../../test_helpers.dart';

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  testWidgets('label options appear while editing and preserve the editor, style, and bounds', (tester) async {
    final original = _stylingShape();
    final store = TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [original]));
    await pumpCanvas(tester, store);
    final shape = find.byType(ShapeElementView);
    await _doubleClick(tester, tester.getCenter(shape));
    final resources = tester.widget<ShapeElementView>(shape).resources;
    final editor = find.byKey(const ValueKey('shape-text-editor'));
    final size = find.byKey(const ValueKey('shape-label-size-select'));
    final color = find.byKey(const ValueKey('shape-label-color'));
    expect(size, findsNothing);
    await tester.enterText(editor, '   ');
    await tester.pumpAndSettle();
    expect(size, findsNothing);
    await tester.enterText(editor, 'Label');
    resources.controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pumpAndSettle();
    expect(size, findsOneWidget);
    expect(find.byKey(const ValueKey('shape-label-font-select')), findsOneWidget);
    expect(tester.widget<TextField>(editor).style!.fontSize, 13);
    expect(tester.widget<TextField>(editor).style!.color, original.strokeColor);

    final trigger = find.descendant(of: size, matching: find.byKey(const ValueKey('select-trigger')));
    await tester.ensureVisible(trigger);
    await tester.tap(trigger, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(resources.focusNode.hasFocus, isTrue);
    expect(resources.controller.selection, const TextSelection.collapsed(offset: 2));
    expect(tester.widget<TextField>(editor).style!.fontSize, 14);

    const custom = Color(0xff0000ff);
    tester.widget<ColorControl>(color).onChanged(custom);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(editor).style!.color, custom);
    await tester.enterText(editor, '');
    await tester.pumpAndSettle();
    expect(color, findsNothing);
    await tester.enterText(editor, 'Retyped');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(editor).style!.color, custom);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('shape-text-preview'));
    var style = tester.widget<Text>(preview).style!;
    expect(style.fontSize, 14);
    expect(style.color, custom);
    resources.session.setShapeOptions(original.id, strokeColor: Colors.red);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(preview).style!.color, custom);
    final reset = find.widgetWithText(TextButton, 'Use outline color');
    await tester.ensureVisible(reset);
    await tester.tap(reset, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    resources.session.setSelection([original.id]);
    await tester.pumpAndSettle();
    style = tester.widget<Text>(preview).style!;
    expect(style.color, Colors.red);
    expect(style.fontSize, 14);
    expect(resources.data.size, original.size);
    await pumpPastSave(tester);
    expect((store.persisted!.elements.single as ShapeElementData).labelFontSize, 14);
  });

  testWidgets('clearing a label invalidates a pending font choice before retyping', (tester) async {
    final shape = _stylingShape().copyWith(text: 'Label');
    final model = testShapeFixture(shape);
    final session = model.session..setActive(shape.id);
    final first = Completer<void>();
    final second = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: ShapeLabelSettings(
            session: session,
            id: shape.id,
            colorPickerExpanded: false,
            onColorPickerExpandedChanged: (_) {},
            loadFont: (family) => family == 'Abel' ? first.future : second.future,
          ),
        ),
      ),
    );
    void choose(String family) =>
        tester.widget<SearchableSelect<String>>(find.byType(SearchableSelect<String>)).onChanged!(family);
    choose('Abel');
    session
      ..setShapeText(shape.id, '')
      ..setShapeText(shape.id, 'New label');
    await tester.pump();
    choose('ABeeZee');
    await tester.pump();
    first.complete();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect((session.element(shape.id)! as ShapeElementData).labelFontFamily, isNull);
    second.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect((session.element(shape.id)! as ShapeElementData).labelFontFamily, 'ABeeZee');
  });

  testWidgets('font search and custom label color take focus without closing the shape editor', (tester) async {
    final original = _stylingShape().copyWith(text: 'Label', labelFontFamily: 'Missing saved font');
    await pumpCanvas(
      tester,
      TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [original])),
    );
    final shape = find.byType(ShapeElementView);
    await _doubleClick(tester, tester.getCenter(shape));
    final resources = tester.widget<ShapeElementView>(shape).resources;
    final editor = find.byKey(const ValueKey('shape-text-editor'));
    resources.controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    final font = find.byKey(const ValueKey('shape-label-font-select'));
    final fontTrigger = find.descendant(of: font, matching: find.byKey(const ValueKey('searchable-select-trigger')));
    await tester.ensureVisible(fontTrigger);
    await tester.tap(fontTrigger, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('searchable-select-search'));
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    expect(editor, findsOneWidget);
    await tester.enterText(search, defaultFontFamily);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(resources.data.labelFontFamily, defaultFontFamily);
    expect(resources.focusNode.hasFocus, isTrue);
    expect(resources.controller.selection, const TextSelection.collapsed(offset: 2));

    final labelColor = find.byKey(const ValueKey('shape-label-color'));
    final custom = find.descendant(of: labelColor, matching: find.byKey(const ValueKey('color-picker-toggle')));
    await tester.ensureVisible(custom);
    await tester.tap(custom, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final hex = find.descendant(of: labelColor, matching: find.byType(TextField));
    await tester.ensureVisible(hex);
    await tester.tap(hex, kind: PointerDeviceKind.mouse);
    await tester.enterText(hex, '#112233');
    await tester.pumpAndSettle();
    expect(editor, findsOneWidget);
    expect(tester.widget<TextField>(hex).focusNode!.hasFocus, isTrue);
    expect(tester.widget<TextField>(editor).style!.color, const Color(0xff112233));
    expect(resources.controller.selection, const TextSelection.collapsed(offset: 2));
  });

  testWidgets('maximum label size fits the tray on a short viewport without resizing the shape', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final small = _stylingShape().copyWith(
      size: const Size.square(32),
      text: 'Long plain label',
      labelFontFamily: 'Missing saved font',
    );
    await pumpCanvas(
      tester,
      TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [small])),
    );
    final shape = find.byType(ShapeElementView);
    await tester.tap(shape, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final trigger = find.descendant(
      of: find.byKey(const ValueKey('shape-label-size-select')),
      matching: find.byKey(const ValueKey('select-trigger')),
    );
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final maxSize = find.widgetWithText(MenuItemButton, '48');
    await tester.ensureVisible(maxSize);
    await tester.pumpAndSettle();
    await tester.tap(maxSize, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.byKey(const ValueKey('shape-text-preview')));
    expect(label.style!.fontFamily, defaultFontFamily);
    expect(label.style!.fontSize, 48);
    expect(label.data, small.text);
    expect(label.overflow, TextOverflow.clip);
    expect(tester.getSize(shape), small.size);
    expect(tester.takeException(), isNull);
  });

  for (final kind in ShapeKind.values) {
    testWidgets('minimum $kind shape focuses and saves native text', (tester) async {
      final value = ShapeElementData(
        id: 'minimum-${kind.name}',
        kind: kind,
        position: const Offset(140, 180),
        size: const Size.square(32),
        strokeColor: const Color(0xff655a53),
        fillColor: null,
        strokeWidth: 2,
      );
      final store = TestLibraryStore(
        CanvasDocument(background: CanvasBackgroundKind.plain, elements: [value]),
      );
      await pumpCanvas(tester, store);
      final bounds = shapeTextBounds(value.kind, value.size, value.strokeWidth);
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));

      final session = tester.widget<CanvasView>(find.byType(CanvasView)).session;
      final shape = find.byType(ShapeElementView);
      await _doubleClick(tester, tester.getCenter(shape) + const Offset(0, -12));
      final resources = tester.widget<ShapeElementView>(shape).resources;
      expect(session.editing, (id: value.id, field: EditorField.shapeText));
      expect(find.byKey(const ValueKey('shape-text-editor')), findsOneWidget);
      expect(resources.focusNode.hasFocus, isTrue);

      const text = 'native label input';
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
      await tester.pumpAndSettle();
      expect((session.element(value.id)! as ShapeElementData).text, text);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(session.editing, isNull);
      await pumpPastSave(tester);
      expect((store.persisted!.elements.single as ShapeElementData).text, text);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wheel over a fitting shape label pans the canvas without leaving editing', (tester) async {
    final value = ShapeElementData(
      id: 'label',
      kind: ShapeKind.rectangle,
      position: const Offset(140, 180),
      size: const Size(160, 100),
      strokeColor: const Color(0xff655a53),
      fillColor: null,
      strokeWidth: 2,
      text: 'Short label',
    );
    await pumpCanvas(
      tester,
      TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [value])),
    );
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final shape = find.byType(ShapeElementView);
    await _doubleClick(tester, tester.getCenter(shape));
    final resources = tester.widget<ShapeElementView>(shape).resources;
    final position = resources.scrollController.position;
    final canvasOffset = canvas.offset;
    expect(position.maxScrollExtent, position.minScrollExtent);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(const ValueKey('shape-text-editor'))),
        scrollDelta: const Offset(0, 20),
      ),
    );
    await tester.pump();

    expect(position.pixels, position.minScrollExtent);
    expect(canvas.offset, canvasOffset + const Offset(0, 20));
    expect(resources.focusNode.hasFocus, isTrue);
  });

  testWidgets('collapsed shape text field accepts keyboard input', (tester) async {
    final value = ShapeElementData(
      id: 'collapsed',
      kind: ShapeKind.rectangle,
      position: const Offset(140, 180),
      size: const Size.square(32),
      strokeColor: const Color(0xff655a53),
      fillColor: null,
      strokeWidth: 1000,
    );
    final model = testShapeFixture(value);
    final session = model.session;
    final resources = ShapeEditorResources(session, value);
    addTearDown(resources.dispose);
    expect(shapeTextBounds(value.kind, value.size, value.strokeWidth).isEmpty, isTrue);

    session.setActive(value.id);
    resources.enterEditing();
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: model.canvasSize,
              child: ShapeElementView(
                data: model.data,
                resources: resources,
                selected: model.selected,
                active: model.active,
                onActivate: () {},
                onMove: (_) {},
                onResize: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(session.editing, (id: value.id, field: EditorField.shapeText));
    final editor = find.byKey(const ValueKey('shape-text-editor'));
    expect(editor, findsOneWidget);
    expect(tester.getRect(editor).size, Size.zero);
    resources.focusNode.requestFocus();
    await tester.pump();
    expect(resources.focusNode.hasFocus, isTrue);

    const text = 'collapsed bounds input';
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await tester.pump();
    expect((session.element(value.id)! as ShapeElementData).text, text);
    expect(value.text, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.editing, isNull);
    expect(editor, findsNothing);
    expect(find.byKey(const ValueKey('shape-text-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hollow shapes hit their full geometric area', (tester) async {
    final model = testShapeFixture(
      ShapeElementData(
        id: 'ellipse',
        kind: ShapeKind.ellipse,
        position: Offset.zero,
        size: const Size(200, 100),
        strokeColor: const Color(0xff655a53),
        fillColor: null,
        strokeWidth: 2,
      ),
    );
    final resources = ShapeEditorResources(model.session, model.data);
    addTearDown(resources.dispose);
    var backgroundTaps = 0;
    var shapeTaps = 0;
    var topTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => backgroundTaps++,
              ),
            ),
            Positioned(
              left: 100,
              top: 100,
              child: SizedBox.fromSize(
                size: model.canvasSize,
                child: Listener(
                  onPointerDown: (_) => shapeTaps++,
                  child: ShapeElementView(
                    data: model.data,
                    resources: resources,
                    selected: model.selected,
                    active: model.active,
                    onActivate: () {},
                    onMove: (_) {},
                    onResize: (_) {},
                  ),
                ),
              ),
            ),
            Positioned(
              left: 175,
              top: 125,
              width: 50,
              height: 50,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => topTaps++,
                child: const Text('Top'),
              ),
            ),
          ],
        ),
      ),
    );

    final rect = tester.getRect(find.byType(ShapeElementView));
    await tester.tapAt(rect.center + const Offset(60, 0), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(shapeTaps, 1);
    expect(backgroundTaps, 0);

    await tester.tapAt(rect.center, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(topTaps, 1);
    expect(shapeTaps, 1);

    await tester.tapAt(rect.topLeft + const Offset(2, 2), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(shapeTaps, 1);
    expect(backgroundTaps, 1);
  });

  testWidgets('shape labels share fixed bounds and saved outline color', (tester) async {
    const color = Color(0xffdc3f3f);
    final value = ShapeElementData(
      id: 'label',
      kind: ShapeKind.rectangle,
      position: const Offset(140, 180),
      size: const Size(300, 200),
      strokeColor: color,
      fillColor: null,
      strokeWidth: 2,
      text: 'Centered label',
    );
    await pumpCanvas(
      tester,
      TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [value])),
    );
    final shape = find.byType(ShapeElementView);
    final preview = find.byKey(const ValueKey('shape-text-preview'));
    final widget = tester.widget<Text>(preview);
    expect(widget.data, value.text);
    expect(widget.style!.color, color);
    expect(widget.overflow, TextOverflow.clip);
    expect(tester.getRect(preview).center.dx, closeTo(tester.getRect(shape).center.dx, 0.5));
    expect(tester.getRect(preview).center.dy, closeTo(tester.getRect(shape).center.dy, 0.5));

    final longText = List.filled(40, 'long label line').join('\n');
    tester.widget<CanvasView>(find.byType(CanvasView)).session.setShapeText(value.id, longText);
    await tester.pumpAndSettle();
    final overflow = tester.widget<Text>(find.byKey(const ValueKey('shape-text-preview')));
    expect(overflow.data, longText);
    expect(overflow.overflow, TextOverflow.clip);
    final shapeBounds = tester.getRect(find.byType(ShapeElementView));
    final textBounds = shapeTextBounds(value.kind, value.size, value.strokeWidth);
    final previewBounds = tester.getRect(find.byKey(const ValueKey('shape-text-preview')));
    expect(previewBounds.left, greaterThanOrEqualTo(shapeBounds.left + textBounds.left - 0.1));
    expect(previewBounds.top, greaterThanOrEqualTo(shapeBounds.top + textBounds.top - 0.1));
    expect(previewBounds.right, lessThanOrEqualTo(shapeBounds.left + textBounds.right + 0.1));
    expect(previewBounds.bottom, lessThanOrEqualTo(shapeBounds.top + textBounds.bottom + 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded shape editor centers fitting text and keeps overflow caret visible at zoom', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final value = ShapeElementData(
      id: 'label',
      kind: ShapeKind.rectangle,
      position: const Offset(140, 180),
      size: const Size(300, 200),
      strokeColor: const Color(0xff655a53),
      fillColor: null,
      strokeWidth: 2,
      text: 'Centered label',
    );
    await pumpCanvas(
      tester,
      TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [value])),
    );
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
      ..updateScalebyDelta(0.43, focalPoint: Offset.zero);
    await tester.pumpAndSettle();
    expect(canvas.scale, closeTo(1.43, 0.0001));

    final shape = find.byType(ShapeElementView);
    final preview = find.byKey(const ValueKey('shape-text-preview'));
    final previewCenter = tester.getRect(preview).center;
    await _doubleClick(tester, tester.getCenter(shape));
    final resources = tester.widget<ShapeElementView>(shape).resources;

    Offset caretCenter() {
      final editable = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
      final start = editable.getLocalRectForCaret(const TextPosition(offset: 0));
      final end = editable.getLocalRectForCaret(
        TextPosition(offset: resources.controller.selection.extentOffset),
      );
      return editable.localToGlobal(Offset((start.center.dx + end.center.dx) / 2, end.center.dy));
    }

    expect(caretCenter().dx, closeTo(previewCenter.dx, 1));
    expect(caretCenter().dy, closeTo(previewCenter.dy, 1));

    final longText = List.filled(40, 'overflow line').join('\n');
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: longText,
        selection: TextSelection.collapsed(offset: longText.length),
      ),
    );
    await tester.pumpAndSettle();
    final editorBounds = tester.getRect(find.byKey(const ValueKey('shape-text-editor')));
    final editable = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
    final caretRect = editable.getLocalRectForCaret(
      TextPosition(offset: resources.controller.selection.extentOffset),
    );
    final caretGlobal = Rect.fromPoints(
      editable.localToGlobal(caretRect.topLeft),
      editable.localToGlobal(caretRect.bottomRight),
    );
    expect(resources.scrollController.offset, greaterThan(0));
    expect(caretGlobal.top, greaterThanOrEqualTo(editorBounds.top - 1));
    expect(caretGlobal.bottom, lessThanOrEqualTo(editorBounds.bottom + 1));

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value.text,
        selection: TextSelection.collapsed(offset: value.text.length),
      ),
    );
    await tester.pumpAndSettle();
    expect(caretCenter().dx, closeTo(previewCenter.dx, 1));
    expect(caretCenter().dy, closeTo(previewCenter.dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shape text enters natively, preserves selection, and finishes on Enter', (tester) async {
    final value = ShapeElementData(
      id: 'label',
      kind: ShapeKind.rectangle,
      position: const Offset(140, 180),
      size: const Size(300, 200),
      strokeColor: const Color(0xff655a53),
      fillColor: null,
      strokeWidth: 2,
      text: 'hello world',
    );
    await pumpCanvas(
      tester,
      TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [value])),
    );
    final session = tester.widget<CanvasView>(find.byType(CanvasView)).session;
    final shape = find.byType(ShapeElementView);
    await tester.tapAt(tester.getCenter(shape), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(session.activeId, value.id);
    expect(session.editing, isNull);

    await tester.tapAt(const Offset(40, 120), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await _doubleClick(tester, tester.getCenter(shape));
    var view = tester.widget<ShapeElementView>(shape);
    final resources = view.resources;
    final editor = find.byKey(const ValueKey('shape-text-editor'));
    expect(session.editing, (id: value.id, field: EditorField.shapeText));
    expect(resources.focusNode.hasFocus, isTrue);
    expect(resources.controller.selection, TextSelection.collapsed(offset: value.text.length));

    await _doubleClick(tester, tester.getCenter(editor), start: 1000);
    expect(resources.controller.selection.isCollapsed, isFalse);

    resources.controller.value = const TextEditingValue(
      text: 'hello world',
      selection: TextSelection.collapsed(offset: 11),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(session.editing, (id: value.id, field: EditorField.shapeText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'hello world\n', selection: TextSelection.collapsed(offset: 12)),
    );
    await tester.pump();
    expect(resources.controller.text, 'hello world\n');

    resources.controller.value = resources.controller.value.copyWith(
      composing: const TextRange(start: 0, end: 5),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.editing, (id: value.id, field: EditorField.shapeText));

    resources.controller.value = resources.controller.value.copyWith(composing: TextRange.empty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(session.editing, isNull);
    expect(session.activeId, value.id);
    expect(find.byKey(const ValueKey('shape-text-editor')), findsNothing);
    view = tester.widget<ShapeElementView>(shape);
    expect(view.data.text, 'hello world\n');
  });

  testWidgets('shape options and resize finish editing but keep the shape active', (tester) async {
    final value = ShapeElementData(
      id: 'shape',
      kind: ShapeKind.rectangle,
      position: const Offset(140, 180),
      size: const Size(300, 200),
      strokeColor: const Color(0xff655a53),
      fillColor: null,
      strokeWidth: 2,
      text: 'label',
    );
    await pumpCanvas(
      tester,
      TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: [value])),
    );
    final session = tester.widget<CanvasView>(find.byType(CanvasView)).session;
    final shape = find.byType(ShapeElementView);
    await _doubleClick(tester, tester.getCenter(shape));
    expect(session.editing, (id: value.id, field: EditorField.shapeText));

    tester.widget<ToolbarButton>(find.byKey(const ValueKey('shape-option-ellipse'))).onPressed?.call();
    await tester.pumpAndSettle();
    expect(session.editing, isNull);
    expect(session.activeId, value.id);
    expect((session.element(value.id)! as ShapeElementData).kind, ShapeKind.ellipse);

    await _doubleClick(tester, tester.getCenter(shape), start: 1000);
    expect(session.editing, (id: value.id, field: EditorField.shapeText));
    final position = (session.element(value.id)! as ShapeElementData).position;
    await tester.drag(
      find.byKey(const ValueKey('shape-block-handle')),
      const Offset(20, 10),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(session.editing, isNull);
    expect(session.activeId, value.id);
    expect((session.element(value.id)! as ShapeElementData).position, isNot(position));

    await _doubleClick(tester, tester.getCenter(shape), start: 2000);
    expect(session.editing, (id: value.id, field: EditorField.shapeText));
    final size = (session.element(value.id)! as ShapeElementData).size;
    final resize = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('shape-resize-handle'))),
      kind: PointerDeviceKind.mouse,
    );
    await resize.moveBy(const Offset(20, 10));
    await resize.up();
    await tester.pumpAndSettle();
    expect(session.editing, isNull);
    expect(session.activeId, value.id);
    expect((session.element(value.id)! as ShapeElementData).size, isNot(size));
  });

  testWidgets('focused shape paste keeps URL-looking content as label text', (tester) async {
    final attachments = TestAttachmentStore();
    final store = TestLibraryStore(
      CanvasDocument(
        background: CanvasBackgroundKind.plain,
        elements: [
          ShapeElementData(
            id: 'shape',
            kind: ShapeKind.rectangle,
            position: const Offset(140, 180),
            size: const Size(300, 200),
            strokeColor: const Color(0xff655a53),
            fillColor: null,
            strokeWidth: 2,
            text: 'label ',
          ),
        ],
      ),
    );
    await pumpCanvas(tester, store, attachmentStore: attachments);
    final shape = tester.widget<ShapeElementView>(find.byType(ShapeElementView));
    await _doubleClick(tester, tester.getCenter(find.byType(ShapeElementView)));
    expect(shape.resources.focusNode.hasFocus, isTrue);
    shape.resources.controller.selection = const TextSelection.collapsed(offset: 6);

    const url = 'https://example.com/article?source=paste';
    const pastedText = 'label $url';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData' ? const {'text': url} : null,
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.state<EditableTextState>(find.byType(EditableText)).pasteText(SelectionChangedCause.keyboard);
    await tester.pumpAndSettle();
    expect(shape.resources.controller.text, pastedText);
    expect(shape.resources.data.text, pastedText);
    expect(find.byType(MediaElementView), findsNothing);
    expect(attachments.files, isEmpty);
    await pumpPastSave(tester);
    expect((store.persisted!.elements.single as ShapeElementData).text, pastedText);
  });

  testWidgets('shape options fit four per row at desktop and narrow widths', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final width in [1200.0, 500.0]) {
      tester.view.physicalSize = Size(width, 800);
      await pumpCanvas(tester, TestLibraryStore());
      await tester.tap(find.byKey(const ValueKey('toolbar-shape')));
      await tester.pumpAndSettle();

      final options = [
        for (final kind in ShapeKind.values) tester.getRect(find.byKey(ValueKey('shape-option-${kind.name}'))),
      ];
      expect(options[1].top, options.first.top);
      expect(options[2].top, options.first.top);
      expect(options[3].top, options.first.top);
      expect(options[4].top, greaterThan(options.first.top));
      expect(options[5].top, options[4].top);
      for (final option in options) {
        expect(option.width, option.height);
      }
      final noFill = tester.getRect(find.byKey(const ValueKey('shape-fill-none')));
      expect(noFill.width, noFill.height);
      final outline = find.byKey(const ValueKey('shape-outline-color'));
      final fill = find.byKey(const ValueKey('shape-fill-color'));
      for (final swatch in presetColors) {
        final key = ValueKey('color-preset-${swatch.label}');
        final outlineRect = tester.getRect(find.descendant(of: outline, matching: find.byKey(key)));
        final fillRect = tester.getRect(find.descendant(of: fill, matching: find.byKey(key)));
        expect(fillRect.left, outlineRect.left);
        expect(fillRect.size, outlineRect.size);
        expect(fillRect.top - tester.getTopLeft(fill).dy, outlineRect.top - tester.getTopLeft(outline).dy);
        expect(fillRect.top, greaterThan(noFill.bottom));
      }
      final fillLabel = tester.getRect(find.text('Fill'));
      expect(noFill.center.dy, fillLabel.center.dy);
      expect(noFill.right, tester.getRect(fill).right);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('fill palette supports presets, custom alpha, clearing, and undo', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = TestLibraryStore();
    await pumpCanvas(tester, store);
    await tester.tap(find.byKey(const ValueKey('toolbar-shape')));
    await tester.pumpAndSettle();
    final fill = find.byKey(const ValueKey('shape-fill-color'));
    final outline = find.byKey(const ValueKey('shape-outline-color'));
    Finder within(Finder control, String key) => find.descendant(of: control, matching: find.byKey(ValueKey(key)));

    expect(tester.widget<ColorControl>(fill).color, isNull);
    await tester.tap(within(fill, 'color-picker-toggle'));
    await tester.pumpAndSettle();
    expect(within(fill, 'color-picker-custom'), findsOneWidget);
    expect(within(outline, 'color-picker-custom'), findsNothing);
    expect(tester.widget<ColorControl>(fill).color, isNull);

    await tester.tap(within(outline, 'color-picker-toggle'));
    await tester.pumpAndSettle();
    expect(within(outline, 'color-picker-custom'), findsOneWidget);
    await tester.tap(within(outline, 'color-picker-toggle'));
    await tester.pumpAndSettle();
    expect(within(fill, 'color-picker-custom'), findsOneWidget);

    await tester.enterText(find.descendant(of: fill, matching: find.byType(TextField)), '#12345680');
    await tester.pump();
    final custom = tester.widget<ColorControl>(fill).color!;
    expect(custom.toARGB32(), 0x80123456);
    await tester.tap(within(fill, 'color-picker-toggle'));
    await tester.pumpAndSettle();
    await tester.tap(within(fill, 'color-preset-Blue'));
    await tester.pump();
    final blue = presetColors.firstWhere((swatch) => swatch.label == 'Blue').color;
    expect(tester.widget<ColorControl>(fill).color, blue);

    await tester.dragFrom(const Offset(100, 180), const Offset(140, 100), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    ElementFixture<ShapeElementData> model() =>
        canvasElement(tester, tester.widget<ShapeElementView>(find.byType(ShapeElementView)).data);
    expect(model().data.fillColor, blue);
    tester.widget<ColorControl>(fill).onChanged(custom);
    await tester.pump();
    expect(model().data.fillColor, custom);
    await tester.tap(find.byKey(const ValueKey('shape-fill-none')));
    await tester.pumpAndSettle();
    expect(model().data.fillColor, isNull);
    expect(tester.widget<ColorControl>(fill).color, isNull);
    await pumpPastSave(tester);
    expect((store.persisted!.elements.single as ShapeElementData).fillColor, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(model().data.fillColor, custom);
    await pumpPastSave(tester);
    expect((store.persisted!.elements.single as ShapeElementData).fillColor, custom);
  });

  testWidgets('toolbar places one shape, then activates, moves, and resizes', (
    tester,
  ) async {
    await pumpCanvas(tester, TestLibraryStore());

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    final toolbar = find.byKey(const ValueKey('toolbar-shape'));
    expect(tester.widget<ToolbarButton>(toolbar).selected, isTrue);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsOneWidget);
    final colorControl = tester.widget<ColorControl>(find.byKey(const ValueKey('shape-outline-color')));
    final blue = presetColors.firstWhere((swatch) => swatch.label == 'Blue').color;
    expect(colorControl.enableAlpha, isTrue);
    colorControl.onChanged(blue);
    await tester.pump();
    expect(
      tester
          .widget<ToolbarButton>(
            find.byKey(
              const ValueKey('shape-option-roundedRectangle'),
            ),
          )
          .selected,
      isTrue,
    );

    final firstDrag = await tester.startGesture(
      const Offset(100, 180),
      kind: PointerDeviceKind.mouse,
    );
    await firstDrag.moveTo(const Offset(240, 280));
    await tester.pump();
    expect(find.byKey(const ValueKey('shape-preview')), findsOneWidget);
    await firstDrag.up();
    await tester.pump();
    expect(find.byType(ShapeElementView), findsOneWidget);
    expect(
      canvasElement(tester, tester.widget<ShapeElementView>(find.byType(ShapeElementView)).data).data.kind,
      ShapeKind.roundedRectangle,
    );
    expect(
      canvasElement(tester, tester.widget<ShapeElementView>(find.byType(ShapeElementView)).data).data.strokeColor,
      blue,
    );
    final first = canvasElement(tester, tester.widget<ShapeElementView>(find.byType(ShapeElementView)).data);
    expect(first.active, isTrue);
    expect(first.selected, isFalse);
    expect(tester.widget<ToolbarButton>(toolbar).selected, isFalse);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shape-option-roundedRectangle')),
      findsOneWidget,
    );

    final secondDrag = await tester.startGesture(
      const Offset(320, 180),
      kind: PointerDeviceKind.mouse,
    );
    await secondDrag.moveTo(const Offset(440, 260));
    await secondDrag.up();
    await tester.pump();
    expect(find.byType(ShapeElementView), findsOneWidget);

    await tester.tap(toolbar);
    await tester.pump();
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsOneWidget);
    expect(
      tester
          .widget<ToolbarButton>(
            find.byKey(
              const ValueKey('shape-option-roundedRectangle'),
            ),
          )
          .selected,
      isTrue,
    );
    tester.widget<ColorControl>(find.byKey(const ValueKey('shape-outline-color'))).onExpandedChanged(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('color-picker-custom')), findsOneWidget);
    tester.widget<ColorControl>(find.byKey(const ValueKey('shape-outline-color'))).onExpandedChanged(false);
    await tester.pumpAndSettle();
    final thirdDrag = await tester.startGesture(
      const Offset(500, 180),
      kind: PointerDeviceKind.mouse,
    );
    await thirdDrag.moveTo(const Offset(620, 260));
    await thirdDrag.up();
    await tester.pump();
    expect(find.byType(ShapeElementView), findsNWidgets(2));
    expect(
      canvasElement(tester, tester.widget<ShapeElementView>(find.byType(ShapeElementView).last).data).data.kind,
      ShapeKind.roundedRectangle,
    );
    expect(tester.widget<ToolbarButton>(toolbar).selected, isFalse);

    final firstFinder = find.byWidgetPredicate(
      (widget) => widget is ShapeElementView && widget.data.id == first.id,
    );
    final originalPosition = first.data.position;
    final originalSize = first.data.size;
    await tester.tapAt(tester.getCenter(firstFinder), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(first.active, isTrue);
    expect(first.selected, isFalse);
    expect(find.byKey(const ValueKey('shape-block-rotate-control')), findsNothing);
    expect(
      find.byKey(const ValueKey('shape-resize-handle')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('shape-block-handle')),
      const Offset(30, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(first.data.position, originalPosition + const Offset(30, 20));

    await tester.drag(
      find.byKey(const ValueKey('shape-resize-handle')),
      const Offset(40, 30),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(first.data.size, originalSize + const Offset(40, 30));

    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
      ..updateScalebyDelta(-0.5, focalPoint: Offset.zero);
    await tester.pump();
    final beforeDrag = first.canvasPosition;
    final order = controller.childOrder;
    await tester.drag(firstFinder, const Offset(30, 20), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(first.canvasPosition, beforeDrag + const Offset(60, 40));
    expect(controller.getInfo(first.data.id).gsPosition, first.canvasPosition);
    expect(controller.childOrder, order);

    await tester.tap(find.byKey(const ValueKey('shape-block-delete-control')));
    await tester.pump();
    expect(firstFinder, findsNothing);
  });

  testWidgets('active shape options edit, persist, undo, and follow selection rules', (tester) async {
    final store = TestLibraryStore(
      CanvasDocument(
        background: CanvasBackgroundKind.plain,
        elements: [
          ShapeElementData(
            id: 'shape',
            kind: ShapeKind.rectangle,
            position: const Offset(140, 180),
            size: const Size(120, 80),
            strokeColor: const Color(0xff000000),
            fillColor: null,
            strokeWidth: 2,
          ),
        ],
      ),
    );
    await pumpCanvas(tester, store);

    ElementFixture<ShapeElementData> model() =>
        canvasElement(tester, tester.widget<ShapeElementView>(find.byType(ShapeElementView)).data);

    final originalPosition = model().data.position;
    await tester.drag(find.byType(ShapeElementView), const Offset(60, 40), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(model().data.position, isNot(originalPosition));
    expect(model().active, isFalse);
    expect(model().selected, isFalse);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsNothing);

    await tester.tap(find.byType(ShapeElementView), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(model().active, isTrue);
    expect(model().selected, isFalse);
    expect(
      find.byKey(const ValueKey('shape-settings-panel')),
      findsOneWidget,
    );

    tester.widget<ToolbarButton>(find.byKey(const ValueKey('shape-option-ellipse'))).onPressed?.call();
    await tester.pump();
    final green = presetColors.firstWhere((swatch) => swatch.label == 'Green').color;
    final red = presetColors.firstWhere((swatch) => swatch.label == 'Red').color;
    tester.widget<ColorControl>(find.byKey(const ValueKey('shape-outline-color'))).onChanged(green);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('shape-fill-color')),
        matching: find.byKey(const ValueKey('color-preset-Red')),
      ),
    );
    await tester.pump();
    tester.widget<DiscreteSlider>(find.byType(DiscreteSlider)).onChanged!(4);
    await tester.pump();

    final edited = model();
    expect(edited.data.kind, ShapeKind.ellipse);
    expect(edited.data.strokeColor, green);
    expect(edited.data.fillColor, red);
    expect(edited.data.strokeWidth, 4);
    expect(
      tester.widget<ToolbarButton>(find.byKey(const ValueKey('shape-option-ellipse'))).selected,
      isTrue,
    );
    await pumpPastSave(tester);
    expect(store.persisted!.elements.single.toJson(), edited.data.toJson());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byType(ShapeElementView), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(model().active, isTrue);
    expect(model().selected, isTrue);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byType(ShapeElementView), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(model().active, isTrue);
    expect(model().selected, isFalse);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsOneWidget);

    await tester.tapAt(const Offset(40, 120), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(model().active, isFalse);

    final marquee = await tester.startGesture(
      const Offset(100, 140),
      kind: PointerDeviceKind.mouse,
    );
    await marquee.moveTo(const Offset(300, 300));
    await marquee.up();
    await tester.pumpAndSettle();
    expect(model().selected, isTrue);
    expect(model().active, isFalse);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(model().data.strokeWidth, 2);
    expect(model().data.kind, ShapeKind.ellipse);
  });
}

ShapeElementData _stylingShape() => ShapeElementData(
  id: 'styled-shape',
  kind: ShapeKind.rectangle,
  position: const Offset(140, 180),
  size: const Size(220, 120),
  strokeColor: const Color(0xff655a53),
  fillColor: null,
  strokeWidth: 2,
);

Future<void> _doubleClick(WidgetTester tester, Offset position, {int start = 100}) async {
  final first = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await first.down(position, timeStamp: Duration(milliseconds: start));
  await first.up(timeStamp: Duration(milliseconds: start + 20));
  await tester.pump(const Duration(milliseconds: 80));
  final second = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await second.down(position, timeStamp: Duration(milliseconds: start + 100));
  await second.up(timeStamp: Duration(milliseconds: start + 120));
  await tester.pumpAndSettle();
}
