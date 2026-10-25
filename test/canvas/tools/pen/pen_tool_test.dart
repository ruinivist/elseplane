// Verifies freehand path geometry, drawing, selection, and persistence.
// Exercises the pen tool through model and canvas widget flows.

import 'dart:convert';
import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/canvas/editor/tools/pen_tool.dart';
import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/widgets/canvas_file_picker.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/main.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/labeled_switch.dart';
import 'package:elseplane/ui/common/select.dart';
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
    await preferences.remove(PreferencesLibraryStore.libraryKey);
  });

  testWidgets('toolbar displays tool icons', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    const tools = ['text', 'code', 'shape', 'draw', 'erase', 'arrow'];
    for (final tool in tools) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('toolbar-$tool')),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('keyboard shortcuts toggle tools and escape disables them', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    const shortcuts = [
      (LogicalKeyboardKey.keyT, 'text'),
      (LogicalKeyboardKey.keyC, 'code'),
      (LogicalKeyboardKey.keyS, 'shape'),
      (LogicalKeyboardKey.keyP, 'draw'),
      (LogicalKeyboardKey.keyE, 'erase'),
      (LogicalKeyboardKey.keyA, 'arrow'),
    ];
    for (final (key, name) in shortcuts) {
      final button = find.byKey(ValueKey('toolbar-$name'));
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(tester.widget<ToolbarButton>(button).selected, isTrue);

      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(tester.widget<ToolbarButton>(button).selected, isFalse);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected,
      isFalse,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected,
      isFalse,
    );
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.tapAt(const Offset(100, 160));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('text-markdown-editor')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(
      tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected,
      isFalse,
    );
    FocusManager.instance.primaryFocus?.unfocus();
  });

  test('pen normalizes pressure and filters non-owner or nearby points', () {
    final strokes = <RawPenStroke>[];
    final tool = PenTool(session: testSessionProvider(), onStroke: strokes.add)
      ..onPointerDown(
        const PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          pressure: 0.5,
          pressureMin: 0.2,
          pressureMax: 0.8,
        ),
      )
      ..onPointerUpdate(
        const PointerMoveEvent(pointer: 2, position: Offset(10, 0)),
      )
      ..onPointerHover(
        const PointerHoverEvent(pointer: 2, position: Offset(10, 0)),
      )
      ..onPointerUp(
        const PointerUpEvent(pointer: 2, position: Offset(10, 0)),
      )
      ..onPointerUpdate(
        const PointerMoveEvent(pointer: 1, position: Offset(2, 0)),
      )
      ..onPointerUpdate(
        const PointerMoveEvent(
          pointer: 1,
          position: Offset(3, 0),
          pressure: 0.8,
          pressureMin: 0.2,
          pressureMax: 0.8,
        ),
      )
      ..onPointerUp(
        const PointerUpEvent(
          pointer: 1,
          position: Offset(6, 0),
          pressureMin: 0,
          pressureMax: 0,
        ),
      );

    expect(strokes, hasLength(1));
    expect(
      strokes.single.points.map((point) => point.position),
      const [Offset.zero, Offset(3, 0), Offset(6, 0)],
    );
    expect(strokes.single.points.first.pressure, closeTo(0.5, 0.0001));
    expect(strokes.single.points[1].pressure, closeTo(1, 0.0001));
    expect(strokes.single.points.last.pressure, 0.5);
    tool.dispose();
  });

  test('pen defers smoothing changes until the active stroke finishes', () {
    final strokes = <RawPenStroke>[];
    final tool = PenTool(session: testSessionProvider(), onStroke: strokes.add)
      ..onPointerDown(const PointerDownEvent(pointer: 1))
      ..setStreamline(1)
      ..onPointerUp(const PointerUpEvent(pointer: 1, position: Offset(4, 0)))
      ..onPointerDown(const PointerDownEvent(pointer: 2))
      ..onPointerUp(const PointerUpEvent(pointer: 2, position: Offset(4, 0)));

    expect(strokes.map((stroke) => stroke.streamline), [penStreamlineDefault, 1]);
    tool.dispose();
  });

  test('pen cancellation discards while mouse exit commits once', () {
    final strokes = <RawPenStroke>[];
    final tool = PenTool(session: testSessionProvider(), onStroke: strokes.add)
      ..onPointerDown(const PointerDownEvent(pointer: 1))
      ..onPointerCancel(
        const PointerCancelEvent(pointer: 1, position: Offset(4, 0)),
      )
      ..onPointerCancel(const PointerCancelEvent(pointer: 1))
      ..onPointerDown(
        const PointerDownEvent(pointer: 2, position: Offset(10, 0)),
      )
      ..onPointerExit(
        const PointerExitEvent(pointer: 2, position: Offset(14, 0)),
      )
      ..onPointerExit(const PointerExitEvent(pointer: 2));

    expect(strokes, hasLength(1));
    expect(tool.active, isFalse);
    tool.dispose();
  });

  test('discarded pen strokes apply queued options to the next stroke', () {
    final strokes = <RawPenStroke>[];
    final tool = PenTool(session: testSessionProvider(), onStroke: strokes.add)
      ..onPointerDown(const PointerDownEvent(pointer: 1))
      ..setColor(Colors.red)
      ..setStrokeWidth(8)
      ..setStreamline(1)
      ..cancel()
      ..onPointerUp(const PointerUpEvent(pointer: 1))
      ..onPointerDown(const PointerDownEvent(pointer: 2))
      ..onPointerUp(const PointerUpEvent(pointer: 2));
    expect(strokes, hasLength(1));
    expect(strokes.single.color, Colors.red);
    expect(strokes.single.width, 8);
    expect(strokes.single.streamline, 1);
    tool.dispose();
  });

  test('positioned pen models keep durable geometry when moved', () {
    final model = testPenModel(
      PenElementData(
        id: 'pen',
        position: const Offset(10, 20),
        size: const Size(61, 61),
        hitSlop: 3,
        color: const Color(0xff000000),
        width: 2.5,
        points: const [
          PenPointData(Offset(5.5, 5.5), pressure: 0.5),
        ],
      ),
    )..moveBy(const Offset(8, -4));

    expect(model.data.position, const Offset(18, 16));
    expect(model.data.size, const Size(61, 61));
    expect(model.data.points.single.position.dx, 5.5);
    model.dispose();
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

  test('arrow movement shifts every durable point equally', () {
    final model = testArrowFixture(
      ArrowElementData(
        id: 'arrow',
        start: Offset.zero,
        controls: const [Offset(20, -8)],
        end: const Offset(40, 10),
        color: const Color(0xff000000),
        strokeStyle: ArrowStrokeStyle.solid,
        strokeWidth: 2,
      ),
    );
    final before = model.geometry;

    model.moveBy(const Offset(12, 7));

    expect(model.geometry.start, before.start + const Offset(12, 7));
    expect(model.geometry.controls.single, before.controls.single + const Offset(12, 7));
    expect(model.geometry.end, before.end + const Offset(12, 7));
  });

  testWidgets('all element types restore in document order', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(40, 160));
    await tester.pump();
    await tester.pump();
    final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    final textPosition = text.data.position;
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      'saved text',
    );

    await _placeCodeBlock(tester, const Offset(120, 140));
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources
      ..setLanguage(CodeLanguage.json)
      ..controller.text = '{"saved": true}';
    final codePosition = code.data.position;
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.dragFrom(
      const Offset(40, 520),
      const Offset(100, 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final pen = tester.widget<PenElementView>(find.byType(PenElementView)).resources;
    final penPosition = pen.data.position;
    final penSize = pen.data.size;
    final penPoints = pen.data.toJson()['points'];
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-arrow')));
    await tester.pump();
    final arrowDrag = await tester.startGesture(
      const Offset(520, 520),
      kind: PointerDeviceKind.mouse,
    );
    await arrowDrag.moveTo(const Offset(700, 560));
    await arrowDrag.up();
    await tester.pump();
    final arrow = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
    final arrowGeometry = arrow.geometry;

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pump();
    await tester.tap(find.text('Canvas'));
    await tester.pump();
    tester
        .widget<Select<CanvasBackgroundKind>>(
          find.byKey(const ValueKey('canvas-background-select')),
        )
        .onChanged!
        .call(CanvasBackgroundKind.plain);
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();

    final document = (await PreferencesLibraryStore().load())!.current.document!;
    final ids = document.elements.map((element) => element.id).toList();
    expect(document.background, CanvasBackgroundKind.plain);
    expect(document.elements, hasLength(4));
    expect(document.elements.map((element) => element.type), [
      'text',
      'code',
      'pen',
      'arrow',
    ]);
    expect((document.elements[0] as TextElementData).markdown, 'saved text');
    expect((document.elements[0] as TextElementData).position, textPosition);
    expect(
      (document.elements[1] as CodeElementData).language,
      CodeLanguage.json,
    );
    expect((document.elements[1] as CodeElementData).position, codePosition);
    expect((document.elements[2] as PenElementData).position, penPosition);
    expect((document.elements[2] as PenElementData).size, penSize);
    expect(
      (document.elements[2] as PenElementData).toJson()['points'],
      penPoints,
    );
    expect(
      (document.elements[3] as ArrowElementData).start,
      arrowGeometry.start,
    );
    expect(
      (document.elements[3] as ArrowElementData).controls.single,
      arrowGeometry.controls.single,
    );
    expect((document.elements[3] as ArrowElementData).end, arrowGeometry.end);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    final restored = (await PreferencesLibraryStore().load())!.current.document!;
    expect(restored.elements.map((element) => element.id), ids);
    expect(find.byType(TextElementView), findsOneWidget);
    expect(find.byType(CodeElementView), findsOneWidget);
    expect(find.byType(PenElementView), findsOneWidget);
    expect(find.byType(ArrowElementView), findsOneWidget);
    final restoredCanvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    expect(
      restoredCanvas.controller.widgetsWithScreenPositions().map(
        (child) => child.id,
      ),
      ids,
    );
    for (final block in tester.widgetList<TextElementView>(find.byType(TextElementView))) {
      expect(block.resources.selected, isFalse);
      expect(block.resources.focusNode.hasFocus, isFalse);
    }
    for (final block in tester.widgetList<CodeElementView>(find.byType(CodeElementView))) {
      expect(block.resources.selected, isFalse);
      expect(block.resources.focusNode.hasFocus, isFalse);
    }
    expect(
      tester.widget<CodeElementView>(find.byType(CodeElementView)).resources.data.source,
      '{"saved": true}',
    );
    expect(
      tester.widget<TextElementView>(find.byType(TextElementView)).resources.data.position,
      textPosition,
    );
    expect(
      tester.widget<CodeElementView>(find.byType(CodeElementView)).resources.data.position,
      codePosition,
    );
    final restoredPen = tester.widget<PenElementView>(find.byType(PenElementView)).resources;
    expect(restoredPen.data.position, penPosition);
    expect(restoredPen.data.size, penSize);
    expect(restoredPen.data.toJson()['points'], penPoints);
    final restoredArrow = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
    expect(restoredArrow.geometry.start, arrowGeometry.start);
    expect(restoredArrow.geometry.controls.single, arrowGeometry.controls.single);
    expect(restoredArrow.geometry.end, arrowGeometry.end);
  });

  testWidgets('pen commits inactive strokes and stays enabled', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.dragFrom(const Offset(100, 200), const Offset(80, 40), kind: PointerDeviceKind.mouse);
    await tester.dragFrom(const Offset(100, 300), const Offset(80, 40));
    await tester.pump();

    expect(find.byType(PenElementView), findsNWidgets(2));
    expect(
      tester.widgetList<PenElementView>(find.byType(PenElementView)).map((stroke) => stroke.resources.active),
      everyElement(isFalse),
    );
    expect(find.byKey(const ValueKey('pen-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('pen-block-handle')), findsNothing);
    expect(find.byKey(const ValueKey('pen-block-delete-control')), findsNothing);
  });

  testWidgets('inactive pen does not draw', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('draw-settings-panel')), findsNothing);
    expect(find.byKey(const ValueKey('pen-preview')), findsNothing);

    await tester.dragFrom(const Offset(100, 200), const Offset(80, 40));
    await tester.pump();

    expect(find.byType(PenElementView), findsNothing);
  });

  testWidgets('pen and arrow interactions preserve stacking order', (
    tester,
  ) async {
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        PenElementData(
          autoArrange: false,
          id: 'pen',
          position: const Offset(100, 250),
          size: const Size(100, 30),
          hitSlop: 6,
          color: const Color(0xff000000),
          width: 3,
          points: const [
            PenPointData(Offset(0, 15), pressure: 0.5),
            PenPointData(Offset(100, 15), pressure: 0.5),
          ],
        ),
        ArrowElementData(
          autoArrange: false,
          id: 'arrow',
          start: const Offset(300, 250),
          controls: const [Offset(380, 235)],
          end: const Offset(460, 250),
          color: const Color(0xff000000),
          strokeStyle: ArrowStrokeStyle.solid,
          strokeWidth: 2,
        ),
      ],
    );
    await SharedPreferencesAsync().setString(
      PreferencesLibraryStore.libraryKey,
      jsonEncode(CanvasLibrary.initial(document).toJson()),
    );
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    final penFinder = find.byType(PenElementView);
    final arrowFinder = find.byType(ArrowElementView);
    final pen = tester.widget<PenElementView>(penFinder).resources;
    final arrow = canvasElement(tester, tester.widget<ArrowElementView>(arrowFinder).data);
    List<String> elementIds() => tester
        .widget<LazyCanvas>(find.byType(LazyCanvas))
        .controller
        .widgetsWithScreenPositions()
        .map((child) => child.id)
        .toList();

    expect(elementIds(), ['pen', 'arrow']);

    await tester.tapAt(tester.getCenter(penFinder));
    await tester.pump();
    expect(elementIds(), ['pen', 'arrow']);
    expect(pen.active, isFalse);
    expect(pen.selected, isFalse);
    expect(find.byKey(const ValueKey('pen-block-handle')), findsNothing);
    expect(find.byKey(const ValueKey('pen-block-delete-control')), findsNothing);
    expect(find.byKey(const ValueKey('pen-block-rotate-control')), findsNothing);

    final penPosition = tester.getTopLeft(penFinder);
    const penDelta = Offset(32, 18);
    await tester.drag(penFinder, penDelta, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(tester.getTopLeft(penFinder), penPosition + penDelta);
    expect(pen.active, isFalse);
    expect(pen.selected, isFalse);

    final arrowStart =
        tester.getTopLeft(arrowFinder) +
        Offset(
          arrow.start.dx - arrow.bounds.left,
          arrow.start.dy - arrow.bounds.top,
        );
    await tester.tapAt(arrowStart);
    await tester.pump();
    expect(elementIds(), ['pen', 'arrow']);
    expect(pen.active, isFalse);
    expect(arrow.active, isTrue);
    expect(arrow.selected, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(tester.getCenter(penFinder));
    await tester.pump();
    expect(elementIds(), ['pen', 'arrow']);
    expect(pen.selected, isTrue);

    await tester.tapAt(arrowStart);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(elementIds(), ['pen', 'arrow']);
    expect(arrow.selected, isFalse);

    await tester.pump(const Duration(milliseconds: 320));
    final saved = (await PreferencesLibraryStore().load())!.current.document!;
    expect(saved.elements.map((element) => element.id), ['pen', 'arrow']);
  });

  testWidgets('draw settings persist and affect only future strokes', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draw-settings-panel')), findsOneWidget);
    expect(find.textContaining('px'), findsNothing);
    final widthSlider = find.descendant(
      of: find.byKey(const ValueKey('pen-width-slider')),
      matching: find.byType(Slider),
    );
    final smoothingSlider = find.descendant(
      of: find.byKey(const ValueKey('pen-smoothing-slider')),
      matching: find.byType(Slider),
    );
    expect(
      tester.widget<Slider>(widthSlider).label,
      '16',
    );
    expect(tester.widget<Slider>(smoothingSlider).label, '2');
    expect(
      tester
          .widget<SliderTheme>(
            find.descendant(
              of: find.byKey(const ValueKey('pen-width-slider')),
              matching: find.byType(SliderTheme),
            ),
          )
          .data
          .showValueIndicator,
      ShowValueIndicator.onDrag,
    );

    await tester.dragFrom(const Offset(100, 300), const Offset(80, 40));
    await tester.pump();
    expect(tester.widget<ColorControl>(find.byType(ColorControl)).enableAlpha, isTrue);
    await tester.tap(find.byKey(const ValueKey('color-preset-Red')));
    tester.widget<Slider>(widthSlider).onChanged!(2.25);
    tester.widget<Slider>(smoothingSlider).onChanged!(0.75);
    await tester.pump();
    expect(
      tester.widget<Slider>(widthSlider).label,
      '9',
    );
    expect(tester.widget<Slider>(smoothingSlider).label, '3');
    await tester.dragFrom(const Offset(100, 450), const Offset(80, 40));
    await tester.pump();

    final strokes = tester
        .widgetList<PenElementView>(find.byType(PenElementView))
        .map((stroke) => stroke.resources.data)
        .toList();
    expect(strokes, hasLength(2));
    expect(strokes.first.color, isNot(strokes.last.color));
    expect(strokes.first.width, 4);
    expect(strokes.first.streamline, penStreamlineDefault);
    expect(
      strokes.last.color,
      presetColors.firstWhere((swatch) => swatch.label == 'Red').color,
    );
    expect(strokes.last.width, 2.25);
    expect(strokes.last.streamline, 0.75);

    await tester.tap(find.byKey(const ValueKey('toolbar-erase')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draw-settings-panel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Slider>(widthSlider).value,
      2.25,
    );
    expect(
      tester.widget<Slider>(widthSlider).label,
      '9',
    );
    expect(tester.widget<Slider>(smoothingSlider).value, 0.75);
    expect(
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('color-preset-Red')),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('color-picker-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('color-picker-custom')), findsOneWidget);
  });

  testWidgets('toolbar and settings island avoid overlap', (tester) async {
    tester.view.physicalSize = const Size(550, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();

    final toolbar = tester.getRect(
      find.byKey(const ValueKey('toolbar-surface')),
    );
    final settings = tester.getRect(
      find.byKey(const ValueKey('settings-button-surface')),
    );
    final panel = tester.getRect(
      find.byKey(const ValueKey('draw-settings-panel')),
    );
    final title = tester.getRect(
      find.ancestor(of: find.byType(CanvasTitle), matching: find.byType(SingleChildScrollView)),
    );
    expect(title.left, lessThan(toolbar.left));
    expect(title.top, greaterThan(toolbar.bottom));
    expect(toolbar.overlaps(title), isFalse);
    expect(title.overlaps(settings), isFalse);
    expect(title.overlaps(panel), isFalse);
    expect(toolbar.center.dx, tester.view.physicalSize.width / 2);
    expect(settings.top, greaterThanOrEqualTo(toolbar.top));
    expect(panel.top, greaterThan(settings.bottom));
    expect(toolbar.overlaps(settings), isFalse);
    expect(settings.overlaps(panel), isFalse);
  });

  testWidgets('ctrl-click selects only near stroke ink', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.dragFrom(const Offset(40, 300), const Offset(60, 60));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();

    final strokeFinder = find.byType(PenElementView);
    final stroke = tester.widget<PenElementView>(strokeFinder).resources;
    final strokeTopLeft = tester.getTopLeft(strokeFinder);
    final strokeSize = tester.getSize(strokeFinder);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(strokeTopLeft + Offset(strokeSize.width - 2, 2));
    await tester.pump();
    expect(stroke.selected, isFalse);

    await tester.tapAt(tester.getCenter(strokeFinder));
    await tester.pump();
    expect(stroke.selected, isTrue);
    final selectedStrokePosition = tester.getTopLeft(strokeFinder);
    await tester.drag(
      strokeFinder,
      const Offset(48, 36),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(tester.getTopLeft(strokeFinder), selectedStrokePosition);
    await tester.tapAt(tester.getCenter(strokeFinder));
    await tester.pump();
    expect(stroke.selected, isTrue);
    expect(
      find.descendant(
        of: strokeFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );

    await _placeCodeBlock(tester, const Offset(120, 140));
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('code-block-surface'))),
    );
    await tester.pump();
    final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    expect(stroke.selected, isTrue);
    expect(code.selected, isTrue);

    await tester.tapAt(tester.getCenter(strokeFinder));
    await tester.pump();
    expect(stroke.selected, isFalse);
    expect(code.selected, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(const Offset(20, 220));
    await tester.pump();
    expect(code.selected, isFalse);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
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
    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(120, 140));

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
    await _placeCodeBlock(tester, const Offset(120, 140));
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

  testWidgets('enabling pen stops text editing', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 200));
    await tester.pump();
    await tester.pump();

    final model = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    expect(model.editing, isTrue);
    expect(find.byType(ElementTransformControls), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(model.editing, isFalse);
    expect(find.byType(ElementTransformControls), findsNothing);
  });

  testWidgets('code blocks resize from the bottom-right handle', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    await _placeCodeBlock(tester, const Offset(40, 120));
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
    await _placeCodeBlock(tester, const Offset(120, 140));

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

    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(120, 140));
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
    await _placeCodeBlock(tester, const Offset(200, 200));

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

  testWidgets('right and middle drag pan over block controls', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await _placeCodeBlock(tester, const Offset(120, 140));

    final block = find.byType(CodeElementView);
    final model = tester.widget<CodeElementView>(block).resources;
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    final originalGridPosition = canvas.controller.widgetsWithScreenPositions().single.gsPosition;

    final rightDrag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('code-block-surface'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await rightDrag.moveBy(const Offset(80, 60));
    await rightDrag.up();
    await tester.pump();

    expect(canvas.controller.offset, isNot(Offset.zero));
    expect(model.selected, isFalse);
    expect(
      canvas.controller.widgetsWithScreenPositions().single.gsPosition,
      originalGridPosition,
    );

    final offsetAfterRightDrag = canvas.controller.offset;
    final originalSize = model.size;
    final middleDrag = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('code-block-resize-handle')),
      ),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await middleDrag.moveBy(const Offset(40, 30));
    await middleDrag.up();
    await tester.pump();

    expect(canvas.controller.offset, isNot(offsetAfterRightDrag));
    expect(model.size, originalSize);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('right drag pans instead of drawing in Draw mode', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();

    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    final rightDrag = await tester.startGesture(
      const Offset(300, 500),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await rightDrag.moveBy(const Offset(80, 60));
    await rightDrag.up();
    await tester.pump();

    expect(canvas.controller.offset, isNot(Offset.zero));
    expect(find.byType(PenElementView), findsNothing);
  });

  testWidgets('space temporarily hands dragging back to the canvas', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byKey(const ValueKey('pen-preview')), findsOneWidget);
    await tester.dragFrom(const Offset(100, 200), const Offset(80, 40));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byType(PenElementView), findsNothing);

    await tester.dragFrom(const Offset(100, 200), const Offset(80, 40));
    await tester.pump();
    expect(find.byType(PenElementView), findsOneWidget);
  });

  testWidgets('eraser scrubs every overlapping element and saves', (
    tester,
  ) async {
    PenElementData stroke(String id, Offset position) => PenElementData(
      id: id,
      position: position,
      size: const Size(100, 100),
      hitSlop: 6,
      color: const Color(0xff000000),
      width: 3,
      points: const [
        PenPointData(Offset(0, 50), pressure: 0.5),
        PenPointData(Offset(100, 50), pressure: 0.5),
      ],
    );

    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        TextElementData(
          id: 'text-overlap',
          position: const Offset(100, 250),
          width: 280,
          height: 100,
          markdown: 'overlap',
          style: const TextNodeStyle(
            fontFamily: 'Source Serif 4',
            color: Color(0xff201C1A),
          ),
        ),
        CodeElementData(
          id: 'code-overlap',
          position: const Offset(100, 250),
          size: const Size(280, 240),
          language: CodeLanguage.dart,
          source: '',
          title: '',
          showLineNumbers: true,
        ),
        stroke('pen-overlap', const Offset(100, 250)),
        ArrowElementData(
          id: 'arrow-overlap',
          start: const Offset(100, 300),
          controls: const [Offset(150, 300)],
          end: const Offset(200, 300),
          color: const Color(0xff000000),
          strokeStyle: ArrowStrokeStyle.solid,
          strokeWidth: 2,
        ),
        TextElementData(
          id: 'text-drag',
          position: const Offset(500, 250),
          width: 160,
          height: 100,
          markdown: 'drag',
          style: const TextNodeStyle(
            fontFamily: 'Source Serif 4',
            color: Color(0xff201C1A),
          ),
        ),
        stroke('pen-safe', const Offset(100, 450)),
      ],
    );
    await SharedPreferencesAsync().setString(
      PreferencesLibraryStore.libraryKey,
      jsonEncode(CanvasLibrary.initial(document).toJson()),
    );
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.tap(find.byKey(const ValueKey('toolbar-erase')));
    await tester.pump();
    final erase = await tester.startGesture(
      const Offset(150, 300),
      kind: PointerDeviceKind.mouse,
    );
    await erase.moveTo(const Offset(550, 300));
    await erase.up();
    await tester.pump();

    expect(find.byType(TextElementView), findsNothing);
    expect(find.byType(CodeElementView), findsNothing);
    expect(find.byType(ArrowElementView), findsNothing);
    expect(find.byType(PenElementView), findsOneWidget);
    expect(
      tester.widget<PenElementView>(find.byType(PenElementView)).resources.data.id,
      'pen-safe',
    );

    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    final pan = await tester.startGesture(
      const Offset(150, 500),
      kind: PointerDeviceKind.mouse,
    );
    await pan.moveBy(const Offset(40, 20));
    await pan.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(canvas.controller.offset, isNot(Offset.zero));
    expect(find.byType(PenElementView), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    final saved = (await PreferencesLibraryStore().load())!.current.document!;
    expect(saved.elements.map((element) => element.id), ['pen-safe']);
  });
}

// ---------- Test helpers ----------

Future<void> _placeCodeBlock(WidgetTester tester, Offset position) async {
  await tester.tap(find.byKey(const ValueKey('toolbar-code')));
  await tester.pump();
  await tester.tapAt(position);
  await tester.pump();
}
