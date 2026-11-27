// Verifies persisted arrow editing, controls, and selection.

import 'dart:async';
import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../../../test_helpers.dart';

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  testWidgets('draws on blocks, previews the nearest anchor, and keeps the pinned bend', (tester) async {
    final store = TestLibraryStore(
      CanvasDocument(
        background: CanvasBackgroundKind.plain,
        elements: [
          _box('left', const Offset(120, 250)),
          _box('right', const Offset(440, 250)),
          _box('above', const Offset(390, 170)),
        ],
      ),
    );
    await pumpCanvas(tester, store);
    await tester.tap(find.byKey(const ValueKey('toolbar-arrow')));
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.down(const Offset(200, 280)));
    await tester.sendEventToBinding(pointer.move(const Offset(310, 200), buttons: kPrimaryButton | kSecondaryButton));
    // Inside "right", but nearer to the bottom of "above".
    await tester.sendEventToBinding(pointer.move(const Offset(443, 251), buttons: kPrimaryButton));
    await tester.pump();
    final preview =
        tester.widget<CustomPaint>(find.byKey(const ValueKey('arrow-preview'))).painter! as ArrowPreviewPainter;
    expect(preview.preview.snapPoints, const [Offset(440, 250)]);
    expect(preview.preview.geometry.end, const Offset(440, 250));
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();

    ArrowElementView view() => tester.widget(find.byType(ArrowElementView));
    final model = canvasElement(tester, view().data);
    expect(model.data.startAttachment, const ArrowAttachment(targetId: 'left', side: ArrowAnchorSide.right));
    expect(model.data.endAttachment, const ArrowAttachment(targetId: 'above', side: ArrowAnchorSide.bottom));
    expect(model.controls, const [Offset(310, 200)]);
    expect(find.byKey(const ValueKey('arrow-preview')), findsNothing);

    model.session.move(['above'], const Offset(70, -20));
    model.session.finishOperation();
    await tester.pumpAndSettle();
    expect(view().geometry.end, const Offset(510, 230));
    expect(view().geometry.controls, const [Offset(310, 200)]);
    expect(tester.getCenter(find.byKey(const ValueKey('arrow-end-handle'))), const Offset(510, 230));
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    expect(controller.getInfo(model.id).gsPosition, view().geometry.bounds.topLeft);
    await pumpPastSave(tester);
    expect(store.persisted!.elements.whereType<ArrowElementData>().single.endAttachment, model.data.endAttachment);
  });

  testWidgets('endpoint drag cancels without editing and releases as one undoable reattachment', (tester) async {
    final free = _arrowDocument().elements.single as ArrowElementData;
    final arrow = free.copyWith(
      end: const Offset(360, 240),
      endAttachment: const ArrowAttachment(targetId: 'old', side: ArrowAnchorSide.left),
    );
    await pumpCanvas(
      tester,
      TestLibraryStore(
        _arrowDocument().copyWith(
          elements: [arrow, _box('old', const Offset(360, 200)), _box('new', const Offset(540, 270))],
        ),
      ),
    );
    ArrowElementView view() => tester.widget(find.byType(ArrowElementView));
    final model = canvasElement(tester, arrow)..setActive(value: true);
    final tip = find.byKey(const ValueKey('arrow-end-handle'));
    await tester.pump();
    final before = model.session.document;
    final canceled = await tester.startGesture(tester.getCenter(tip), kind: PointerDeviceKind.mouse);
    await canceled.moveTo(const Offset(546, 308));
    await tester.pump();
    expect(view().geometry.end, const Offset(540, 310));
    expect(tester.widget<ArrowEditor>(find.byType(ArrowEditor)).snapPoint, const Offset(540, 310));
    expect(model.session.document, same(before));
    await canceled.cancel();
    await tester.pumpAndSettle();
    expect(model.session.document, same(before));
    expect(view().geometry.end, const Offset(360, 240));
    expect(tester.widget<ArrowEditor>(find.byType(ArrowEditor)).snapPoint, isNull);

    final released = await tester.startGesture(tester.getCenter(tip), kind: PointerDeviceKind.mouse);
    await released.moveTo(const Offset(546, 308));
    await released.up();
    await tester.pumpAndSettle();
    expect(model.data.endAttachment, const ArrowAttachment(targetId: 'new', side: ArrowAnchorSide.left));
    expect(model.data.controls, arrow.controls);
    model.session.undo();
    await tester.pumpAndSettle();
    expect(model.data.endAttachment, arrow.endAttachment);
  });

  testWidgets('a wheel pan resamples a stationary endpoint drag before release', (tester) async {
    final arrow = _arrowDocument().elements.single as ArrowElementData;
    await pumpCanvas(
      tester,
      TestLibraryStore(_arrowDocument().copyWith(elements: [arrow, _box('target', const Offset(540, 270))])),
    );
    ArrowElementView view() => tester.widget(find.byType(ArrowElementView));
    final model = canvasElement(tester, arrow)..setActive(value: true);
    final tip = find.byKey(const ValueKey('arrow-end-handle'));
    await tester.pump();
    const cursor = Offset(540, 310);
    final drag = await tester.startGesture(tester.getCenter(tip), kind: PointerDeviceKind.mouse);
    await drag.moveTo(cursor);
    await tester.pump();
    expect(view().geometry.end, cursor);
    expect(tester.widget<ArrowEditor>(find.byType(ArrowEditor)).snapPoint, cursor);

    const scroll = Offset(0, 150);
    await tester.sendEventToBinding(const PointerScrollEvent(position: cursor, scrollDelta: scroll));
    await tester.pumpAndSettle();
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    expect(controller.offset, scroll);
    expect(tester.widget<ArrowEditor>(find.byType(ArrowEditor)).snapPoint, isNull);
    expect(tester.getCenter(tip), cursor);

    await drag.up();
    await tester.pumpAndSettle();
    expect(model.data.endAttachment, isNull);
    expect(model.end, cursor + scroll);
  });

  testWidgets('natural-height text and a rotated code body provide live measured anchors', (tester) async {
    final arrow = (_arrowDocument().elements.single as ArrowElementData).copyWith(
      startAttachment: const ArrowAttachment(targetId: 'text', side: ArrowAnchorSide.bottom),
      endAttachment: const ArrowAttachment(targetId: 'code', side: ArrowAnchorSide.top),
    );
    final text = TextElementData(
      id: 'text',
      position: const Offset(100, 230),
      width: 180,
      height: null,
      markdown: 'One line',
      style: const TextNodeStyle(fontFamily: defaultFontFamily),
    );
    final code = CodeElementData(
      id: 'code',
      position: const Offset(400, 220),
      size: const Size(280, 240),
      language: CodeLanguage.dart,
      source: '',
      title: 'Not an attachment target',
      showLineNumbers: true,
      rotation: math.pi / 2,
    );
    await pumpCanvas(tester, TestLibraryStore(_arrowDocument().copyWith(elements: [arrow, text, code])));
    await tester.pumpAndSettle();
    ArrowElementView view() => tester.widget(find.byType(ArrowElementView));
    final session = canvasElement(tester, arrow).session;
    final start = view().geometry.start;
    expect(view().geometry.end.dx, closeTo(660, 1e-6));
    expect(view().geometry.end.dy, closeTo(340, 1e-6));

    session.setMarkdown(text.id, List.filled(6, 'Another paragraph').join('\n\n'));
    await tester.pumpAndSettle();
    final textView = find.byType(TextElementView);
    expect(view().geometry.start.dy, greaterThan(start.dy));
    expect(view().geometry.start.dy, closeTo(tester.getBottomLeft(textView).dy, 1e-6));
    expect(view().geometry.start.dx, 190);
    expect(view().geometry.controls, arrow.controls);
  });

  testWidgets('a culled image updates its connector when its size becomes known', (tester) async {
    final arrow = (_arrowDocument().elements.single as ArrowElementData).copyWith(
      endAttachment: const ArrowAttachment(targetId: 'image', side: ArrowAnchorSide.bottom),
    );
    final media = MediaElementData(
      id: 'image',
      position: const Offset(3500, 230),
      width: 220,
      url: 'attachments/71884c52-f3bc-4cea-9289-0af9fdcb5262.png',
    );
    final store = _DeferredAttachmentStore();
    await pumpCanvas(
      tester,
      TestLibraryStore(_arrowDocument().copyWith(elements: [arrow, media])),
      attachmentStore: store,
    );
    await tester.pumpAndSettle();
    ArrowElementView view() => tester.widget(find.byType(ArrowElementView));
    final session = canvasElement(tester, arrow).session;
    final before = session.document;
    expect(find.byType(MediaElementView), findsNothing);
    expect(view().geometry.end, isNot(const Offset(3610, 450)));

    store.image.complete(onePixelPngBytes);
    await pumpUntil(tester, () => view().geometry.end == const Offset(3610, 450));
    expect(find.byType(MediaElementView), findsNothing);
    expect(session.document, same(before));
  });

  test('arrow points edit independently and preserve minimum length', () {
    final model = testArrowFixture(
      ArrowElementData(
        id: 'arrow',
        start: const Offset(10, 20),
        controls: const [Offset(60, 5), Offset(80, 20)],
        end: const Offset(110, 40),
        color: Colors.black,
        strokeStyle: ArrowStrokeStyle.solid,
        strokeWidth: 2,
      ),
    );

    final geometry = model.geometry;
    final snapshot = model.data;
    expect(model.setPoint(1, const Offset(70, 10)), isTrue);
    expect(model.start, const Offset(10, 20));
    expect(model.controls, const [Offset(70, 10), Offset(80, 20)]);
    expect(geometry.controls, const [Offset(60, 5), Offset(80, 20)]);
    expect(snapshot.controls, geometry.controls);
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
  });

  testWidgets('active arrows expose zoom-aware editable points with one-step undo', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_arrowDocument()));
    final arrowFinder = find.byType(ArrowElementView);
    var model = canvasElement(tester, tester.widget<ArrowElementView>(arrowFinder).data);

    expect(find.byKey(const ValueKey('arrow-start-handle')), findsNothing);
    final curvePoint = model.start * 0.25 + model.controls.single * 0.5 + model.end * 0.25;
    await tester.tapAt(
      tester.getTopLeft(arrowFinder) + curvePoint - model.bounds.topLeft,
      kind: PointerDeviceKind.mouse,
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
    model = canvasElement(tester, tester.widget<ArrowElementView>(arrowFinder).data);
    expect(model.end, originalEnd);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('arrow-control-0-handle')), findsNothing);
  });

  testWidgets('multi-handle dragging stays on canvas, edits at zoom, saves and undoes', (tester) async {
    final store = TestLibraryStore(CanvasDocument(background: CanvasBackgroundKind.plain, elements: []));
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
    expect(find.byType(ArrowElementView), findsOneWidget);
    expect(tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-arrow'))).selected, isFalse);
    var model = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
    expect(model.active, isTrue);
    expect(model.controls, const [Offset(100, 150), Offset(180, 110)]);
    expect(model.end, const Offset(260, 170));
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();
    expect(find.byType(ArrowElementView), findsOneWidget);
    expect(find.byKey(const ValueKey('arrow-control-0-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('arrow-control-1-handle')), findsOneWidget);

    final paint = tester
        .widget<CustomPaint>(find.descendant(of: find.byType(ArrowElementView), matching: find.byType(CustomPaint)))
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
    model = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
    expect(model.controls, original);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    model = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
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
    final store = TestLibraryStore(_arrowDocument());
    await pumpCanvas(tester, store);
    final model = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
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
    model.setSelected(value: true);
    await tester.tapAt(model.start, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(model.active, isTrue);
    expect(model.selected, isFalse);
    expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).foregroundChildId, model.data.id);
    expect(canvas.childOrder, order);
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('$platform arrow menu dismissal preserves modifier selection and group dragging', (tester) async {
      var document = _arrowDocument();
      document = document.withElements(
        (elements) => elements.add(
          ArrowElementData(
            id: 'other',
            start: const Offset(480, 350),
            controls: const [Offset(550, 300)],
            end: const Offset(650, 390),
            color: Colors.black,
            strokeStyle: ArrowStrokeStyle.solid,
            strokeWidth: 2,
          ),
        ),
      );
      await pumpCanvas(tester, TestLibraryStore(document), platform: platform);
      final models = tester
          .widgetList<ArrowElementView>(find.byType(ArrowElementView))
          .map((arrow) => canvasElement(tester, arrow.data))
          .toList();
      final first = models.first;
      final second = models.last;
      first.setSelected(value: true);
      second.setSelected(value: true);
      Future<void> openMenu() async {
        final click = await tester.startGesture(second.start, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
        await click.up();
        await tester.pumpAndSettle();
        expect(find.byType(MenuSurface), findsOneWidget);
      }

      await openMenu();
      await tester.tapAt(first.start, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(MenuSurface), findsNothing);
      expect(first.active, isTrue);
      expect(models.every((model) => !model.selected), isTrue);

      await openMenu();
      final modifier = platform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.pump();
      await tester.tapAt(first.start, kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(find.byType(MenuSurface), findsNothing);
      expect(models.every((model) => model.selected && !model.active), isTrue);

      await openMenu();
      final starts = models.map((model) => model.start).toList();
      const delta = Offset(30, 20);
      await tester.dragFrom(first.start, delta, kind: PointerDeviceKind.mouse);
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
    Slider widthSlider() => tester.widget<Slider>(find.byKey(const ValueKey('discrete-slider')));
    expect(widthSlider().label, '5');
    expect(widthSlider().value, 2);
    expect(widthSlider().divisions, 19);
    expect(widthSlider().semanticFormatterCallback!(widthSlider().min), '1');
    expect(widthSlider().semanticFormatterCallback!(widthSlider().max), '20');
    await tester.tap(find.byKey(const ValueKey('arrow-style-dashed')));
    await tester.tap(find.byKey(const ValueKey('color-preset-Red')));
    widthSlider().onChanged!(widthSlider().min);
    await tester.pump();
    expect(widthSlider().label, '1');
    final firstDrag = await tester.startGesture(
      const Offset(120, 200),
      kind: PointerDeviceKind.mouse,
    );
    await firstDrag.moveTo(const Offset(300, 260));
    await tester.pump();
    expect(find.byKey(const ValueKey('arrow-preview')), findsOneWidget);
    expect(find.byType(ArrowElementView), findsNothing);
    await firstDrag.up();
    await tester.pump();

    expect(find.byType(ArrowElementView), findsOneWidget);
    final first = canvasElement(tester, tester.widget<ArrowElementView>(find.byType(ArrowElementView)).data);
    expect(first.start, const Offset(120, 200));
    expect(first.end, const Offset(300, 260));
    expect(first.data.strokeStyle, ArrowStrokeStyle.dashed);
    expect(
      first.data.color.toARGB32(),
      presetColors.firstWhere((swatch) => swatch.label == 'Red').color.toARGB32(),
    );
    expect(first.data.strokeWidth, arrowStrokeWidthMinimum);
    expect(find.byKey(const ValueKey('arrow-settings-panel')), findsOneWidget);
    widthSlider().onChanged!(widthSlider().max);
    await tester.pump();
    expect(widthSlider().label, '20');
    expect(first.data.strokeWidth, arrowStrokeWidthMaximum);
    await tester.tap(find.byKey(const ValueKey('arrow-style-solid')));
    await tester.pump();
    expect(first.data.strokeStyle, ArrowStrokeStyle.solid);
    final toolbar = find.byKey(const ValueKey('toolbar-arrow'));
    expect(tester.widget<ToolbarButton>(toolbar).selected, isFalse);

    final secondDrag = await tester.startGesture(
      const Offset(420, 200),
      kind: PointerDeviceKind.mouse,
    );
    await secondDrag.moveTo(const Offset(560, 260));
    await secondDrag.up();
    await tester.pump();
    expect(find.byType(ArrowElementView), findsOneWidget);

    final arrowFinder = find.byType(ArrowElementView).first;
    final arrowTopLeft = tester.getTopLeft(arrowFinder);
    final startPoint =
        arrowTopLeft +
        Offset(
          first.start.dx - first.bounds.left,
          first.start.dy - first.bounds.top,
        );
    await tester.tapAt(startPoint, kind: PointerDeviceKind.mouse);
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
      color: Colors.black,
      strokeStyle: ArrowStrokeStyle.solid,
      strokeWidth: 2,
    ),
  ],
);

ShapeElementData _box(String id, Offset position) => ShapeElementData(
  id: id,
  kind: ShapeKind.rectangle,
  position: position,
  size: const Size(100, 80),
  strokeColor: Colors.black,
  fillColor: null,
  strokeWidth: 2,
);

class _DeferredAttachmentStore extends TestAttachmentStore {
  final image = Completer<Uint8List>();

  @override
  Future<Uint8List> read(String path) => image.future;
}
