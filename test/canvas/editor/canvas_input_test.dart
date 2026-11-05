// Verifies pointer ownership, cancellation, and tool routing over canvas objects.
// Uses a measured viewport substitute and focused canvas integration.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_input.dart';
import 'package:elseplane/canvas/editor/canvas_view.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EditorSession session;
  late CanvasInput input;
  late _Viewport viewport;
  late List<Offset> quickText;
  var focusedEditor = false;

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
    quickText = [];
    focusedEditor = false;
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
      onQuickText: quickText.add,
      isFocusedEditorAt: (_) => focusedEditor,
      onStroke: (_) {},
      onArrow: (_) {},
      onShape: (_) {},
    );
  });
  tearDown(() {
    input.dispose();
    session.dispose();
  });

  for (final rejection in [
    'drag',
    'cancel',
    'navigation',
    'tool',
    'modifier',
    'timeout',
    'distance',
    'focused',
    'control',
  ]) {
    testWidgets('quick text rejects $rejection', (tester) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      const position = Offset(500, 300);
      focusedEditor = rejection == 'focused';
      input.pointerDown(pointer.down(position, timeStamp: const Duration(milliseconds: 100)));
      if (rejection == 'drag') {
        input
          ..pointerMove(pointer.move(position + const Offset(30, 0)))
          ..pointerMove(pointer.move(position));
      }
      if (rejection == 'cancel') {
        input.pointerCancel(pointer.cancel());
      } else {
        input.pointerUp(pointer.up(timeStamp: const Duration(milliseconds: 120)));
      }
      if (rejection == 'navigation') input.cancelQuickText();
      if (rejection == 'tool') input.chooseTool(CanvasTool.pen);
      if (rejection == 'modifier') input.modifierPressed.value = true;
      if (rejection == 'control') {
        final control = TestPointer(3, PointerDeviceKind.mouse);
        input.target('a').pointerDown(control.down(Offset.zero), control: true);
        input.pointerUp(control.up());
      }
      final secondPosition = rejection == 'distance' ? position + const Offset(200, 0) : position;
      final time = rejection == 'timeout' ? 1000 : 200;
      input
        ..pointerDown(pointer.down(secondPosition, timeStamp: Duration(milliseconds: time)))
        ..pointerUp(pointer.up(timeStamp: Duration(milliseconds: time + 20)));
      expect(quickText, isEmpty);
    });
  }

  for (final surface in ['empty', 'shape', 'text', 'code', 'media']) {
    testWidgets('mouse quick text over $surface keeps focus', (tester) async {
      SharedPreferencesAsyncWeb.registerWith(null);
      final elements = <CanvasElementData>[
        if (surface == 'shape') session.document.elements.first,
        if (surface == 'text')
          TextElementData(
            id: 'existing',
            position: Offset.zero,
            width: 300,
            height: 240,
            markdown: 'Existing text',
            style: const TextNodeStyle(fontFamily: 'JetBrains Mono'),
          ),
        if (surface == 'code')
          CodeElementData(
            id: 'existing',
            position: Offset.zero,
            size: const Size(300, 240),
            language: CodeLanguage.dart,
            source: 'final value = 1;',
            title: '',
            showLineNumbers: false,
          ),
        if (surface == 'media')
          MediaElementData(
            id: 'existing',
            position: Offset.zero,
            width: 300,
            url: '',
          ),
      ];
      await pumpCanvas(
        tester,
        TestLibraryStore(
          CanvasDocument(
            background: CanvasBackgroundKind.plain,
            elements: elements,
          ),
        ),
      );
      final editor = tester.widget<CanvasView>(find.byType(CanvasView)).session;
      final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller
        ..updateScalebyDelta(0.25, focalPoint: Offset.zero)
        ..scrollBy(const Offset(-160, -180));
      await tester.pumpAndSettle();
      final position = surface == 'empty'
          ? const Offset(520, 400)
          : (const Offset(40, 40) - canvas.offset) * canvas.scale;
      final expected = canvas.offset + position / canvas.scale;
      await _doubleClick(tester, position, PointerDeviceKind.mouse);
      expect(editor.document.elements.length, elements.length + 1);
      final value = editor.document.elements.last as TextElementData;
      expect(value.position, expected);
      expect(value.style.background, BlockBackgroundKind.transparent);
      expect(editor.activeId, value.id);
      expect(editor.editing, (id: value.id, field: EditorField.markdown));
      final view = tester
          .widgetList<TextElementView>(find.byType(TextElementView))
          .firstWhere((view) => view.data.id == value.id);
      expect(view.resources.focusNode.hasFocus, isTrue);
      await tester.enterText(find.byKey(const ValueKey('text-markdown-editor')), 'Quick text');
      editor
        ..editField(null)
        ..undo();
      expect((editor.element(value.id)! as TextElementData).markdown, '');
      editor.undo();
      expect(editor.element(value.id), isNull);
      editor.redo();
      expect((editor.element(value.id)! as TextElementData).style.background, BlockBackgroundKind.transparent);
    });
  }

  testWidgets('focused editors keep double-click selection', (tester) async {
    SharedPreferencesAsyncWeb.registerWith(null);
    await pumpCanvas(tester, TestLibraryStore());
    await _doubleClick(tester, const Offset(120, 200), PointerDeviceKind.mouse);
    await tester.enterText(find.byKey(const ValueKey('text-markdown-editor')), 'hello world');
    final editor = tester.widget<CanvasView>(find.byType(CanvasView)).session;
    final field = find.byKey(const ValueKey('text-markdown-editor'));
    await _doubleClick(tester, tester.getTopLeft(field) + const Offset(45, 36), PointerDeviceKind.mouse, start: 1000);
    expect(editor.document.elements, hasLength(1));
    final view = tester.widget<TextElementView>(find.byType(TextElementView));
    expect(view.resources.focusNode.hasFocus, isTrue);
    expect(view.resources.controller.selection.isCollapsed, isFalse);
  });

  for (final field in ['code', 'title', 'media']) {
    testWidgets('focused $field field keeps double-click gestures', (tester) async {
      SharedPreferencesAsyncWeb.registerWith(null);
      await pumpCanvas(tester, TestLibraryStore());
      final editor = tester.widget<CanvasView>(find.byType(CanvasView)).session
        ..chooseTool(field == 'media' ? CanvasTool.media : CanvasTool.code);
      await tester.tapAt(const Offset(120, 200), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final finder = find.byKey(
        ValueKey(switch (field) {
          'code' => 'code-block-preview-surface',
          'title' => 'code-title-input',
          _ => 'media-url-field',
        }),
      );
      final position = field == 'title' ? tester.getCenter(finder) : tester.getTopLeft(finder) + const Offset(45, 20);
      await tester.tapAt(position, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final focus = FocusManager.instance.primaryFocus;
      await _doubleClick(tester, position, PointerDeviceKind.mouse, start: 1000);
      expect(editor.document.elements, hasLength(1));
      expect(FocusManager.instance.primaryFocus, same(focus));
    });
  }

  for (final type in ['text', 'code', 'shape', 'media']) {
    testWidgets('$type resize handle rejects mouse quick text', (tester) async {
      SharedPreferencesAsyncWeb.registerWith(null);
      const position = Offset(120, 200);
      final element = switch (type) {
        'text' => TextElementData(
          id: 'existing',
          position: position,
          width: 240,
          height: 220,
          markdown: 'Existing',
          style: const TextNodeStyle(fontFamily: 'JetBrains Mono'),
        ),
        'code' => CodeElementData(
          id: 'existing',
          position: position,
          size: const Size(300, 260),
          language: CodeLanguage.dart,
          source: 'final value = 1;',
          title: '',
          showLineNumbers: false,
        ),
        'media' => MediaElementData(
          id: 'existing',
          position: position,
          width: 240,
          url: 'attachments/00000000-0000-4000-8000-000000000000.png',
        ),
        _ => (session.document.elements.first as ShapeElementData).copyWith(id: 'existing', position: position),
      };
      await pumpCanvas(
        tester,
        TestLibraryStore(
          CanvasDocument(
            background: CanvasBackgroundKind.plain,
            elements: [element],
          ),
        ),
        attachmentStore: TestAttachmentStore({
          'attachments/00000000-0000-4000-8000-000000000000.png': onePixelPngBytes,
        }),
      );
      final editor = tester.widget<CanvasView>(find.byType(CanvasView)).session..setActive('existing');
      await tester.pumpAndSettle();
      if (type == 'media') {
        await pumpUntil(tester, () => find.byKey(const ValueKey('media-resize-handle')).evaluate().isNotEmpty);
      }
      final handle = find.byKey(
        ValueKey(
          type == 'text' || type == 'code' ? '$type-block-resize-handle' : '$type-resize-handle',
        ),
      );
      await _doubleClick(tester, tester.getCenter(handle), PointerDeviceKind.mouse);
      expect(editor.document.elements, [element]);
      expect(editor.editing, isNull);
      final drag = await tester.startGesture(tester.getCenter(handle), kind: PointerDeviceKind.mouse);
      await drag.moveBy(const Offset(30, 20));
      await drag.moveBy(const Offset(30, 20));
      await drag.up();
      await tester.pumpAndSettle();
      expect(editor.document.elements, hasLength(1));
      expect(editor.document.elements.single, isNot(element));
    });
  }

  test('tool changes reject stale callbacks before a new target gesture', () {
    final first = TestPointer(1, PointerDeviceKind.mouse);
    final oldTarget = input.target('a')
      ..pointerDown(first.down(const Offset(30, 30)), control: true)
      ..transform(() => session.move(['a'], const Offset(10, 0)));
    input
      ..chooseTool(CanvasTool.pen)
      ..pointerUp(first.up());
    oldTarget.transform(() => session.move(['a'], const Offset(100, 0)));
    input.chooseTool(CanvasTool.select);
    final second = TestPointer(2, PointerDeviceKind.mouse);
    final current = input.target('a')..pointerDown(second.down(const Offset(40, 30)), control: true);
    oldTarget.transform(() => session.move(['a'], const Offset(100, 0)));
    current.transform(() => session.move(['a'], const Offset(20, 0)));
    input.pointerUp(second.up());
    current.finish();
    expect((session.element('a')! as ShapeElementData).position, const Offset(30, 0));
    session.undo();
    expect((session.element('a')! as ShapeElementData).position, const Offset(10, 0));
    current.move(const Offset(100, 0));
    expect((session.element('a')! as ShapeElementData).position, const Offset(10, 0));
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

  testWidgets('finger gestures leave canvas edits to Grid navigation', (tester) async {
    SharedPreferencesAsyncWeb.registerWith(null);
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        PenElementData(
          id: 'pen',
          position: const Offset(100, 250),
          size: const Size(100, 100),
          hitSlop: 6,
          color: const Color(0xff000000),
          width: 3,
          points: const [PenPointData(Offset(0, 50), pressure: 0.5), PenPointData(Offset(100, 50), pressure: 0.5)],
        ),
        CodeElementData(
          id: 'code',
          position: const Offset(250, 220),
          size: const Size(280, 240),
          language: CodeLanguage.dart,
          source: 'value',
          title: 'title',
          showLineNumbers: true,
        ),
      ],
    );
    await pumpCanvas(tester, TestLibraryStore(document));
    final editor = tester.widget<CanvasView>(find.byType(CanvasView)).session;
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    const touch = PointerDeviceKind.touch;

    final navigation = await tester.startGesture(const Offset(650, 450));
    await navigation.moveBy(const Offset(60, 30));
    await navigation.up();
    await tester.pumpAndSettle();
    expect(canvas.offset, isNot(Offset.zero));

    for (final tool in [CanvasTool.pen, CanvasTool.arrow, CanvasTool.shape]) {
      editor.chooseTool(tool);
      final draw = await tester.startGesture(const Offset(650, 450));
      await draw.moveBy(const Offset(60, 30));
      await draw.up();
      await tester.pumpAndSettle();
      expect(editor.document.elements.map((element) => element.id), ['pen', 'code']);
    }

    for (final tool in [CanvasTool.text, CanvasTool.code, CanvasTool.media]) {
      editor.chooseTool(tool);
      await tester.tapAt(const Offset(650, 450));
      await tester.pumpAndSettle();
      expect(editor.document.elements.map((element) => element.id), ['pen', 'code']);
    }

    editor.chooseTool(CanvasTool.select);
    await _doubleClick(tester, const Offset(650, 450), touch);
    expect(editor.document.elements.map((element) => element.id), ['pen', 'code']);

    final position = (editor.element('code')! as CodeElementData).position;
    final move = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('code-block-preview-surface'))),
    );
    await move.moveBy(const Offset(60, 30));
    await move.up();
    await tester.pumpAndSettle();
    expect((editor.element('code')! as CodeElementData).position, position);

    editor.setActive('code');
    await tester.pumpAndSettle();
    final size = (editor.element('code')! as CodeElementData).size;
    final resize = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('code-block-resize-handle'))),
    );
    await resize.moveBy(const Offset(60, 30));
    await resize.up();
    await tester.pumpAndSettle();
    expect((editor.element('code')! as CodeElementData).size, size);

    editor.chooseTool(CanvasTool.eraser);
    final erase = await tester.startGesture(tester.getCenter(find.byType(PenElementView)));
    await erase.moveBy(const Offset(60, 30));
    await erase.up();
    await tester.pumpAndSettle();
    expect(editor.document.elements.map((element) => element.id), ['pen', 'code']);
  });

  testWidgets('mouse and stylus still draw strokes', (tester) async {
    SharedPreferencesAsyncWeb.registerWith(null);
    await pumpCanvas(tester, TestLibraryStore());
    final editor = tester.widget<CanvasView>(find.byType(CanvasView)).session..chooseTool(CanvasTool.pen);

    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.stylus]) {
      final start = Offset(200 + editor.document.elements.length * 100, 300);
      final draw = await tester.startGesture(start, kind: kind);
      await draw.moveBy(const Offset(60, 30));
      await draw.up();
      await tester.pumpAndSettle();
    }
    expect(editor.document.elements.whereType<PenElementData>(), hasLength(2));
  });

  test('canceling mouse marquee restores the previous selection', () {
    input.chooseTool(CanvasTool.select);
    session.setSelection(['a']);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
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
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    input
      ..pointerDown(pointer.down(const Offset(10, 10), buttons: kSecondaryButton))
      ..pointerMove(pointer.move(const Offset(13, 10)));
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

Future<void> _doubleClick(WidgetTester tester, Offset position, PointerDeviceKind kind, {int start = 100}) async {
  final first = await tester.createGesture(kind: kind);
  await first.down(position, timeStamp: Duration(milliseconds: start));
  await first.up(timeStamp: Duration(milliseconds: start + 20));
  await tester.pump(const Duration(milliseconds: 80));
  final second = await tester.createGesture(kind: kind);
  await second.down(position, timeStamp: Duration(milliseconds: start + 100));
  await second.up(timeStamp: Duration(milliseconds: start + 120));
  await tester.pumpAndSettle();
}
