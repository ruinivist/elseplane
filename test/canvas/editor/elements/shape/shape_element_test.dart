// Verifies persisted shape hit targets, options, and controls.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../../../test_helpers.dart';

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

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
    await tester.tapAt(rect.center + const Offset(60, 0));
    await tester.pump();
    expect(shapeTaps, 1);
    expect(backgroundTaps, 0);

    await tester.tapAt(rect.center);
    await tester.pump();
    expect(topTaps, 1);
    expect(shapeTaps, 1);

    await tester.tapAt(rect.topLeft + const Offset(2, 2));
    await tester.pump();
    expect(shapeTaps, 1);
    expect(backgroundTaps, 1);
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

    await tester.dragFrom(const Offset(100, 180), const Offset(140, 100));
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
    await tester.tapAt(tester.getCenter(firstFinder));
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
    await tester.drag(find.byType(ShapeElementView), const Offset(60, 40));
    await tester.pump();
    expect(model().data.position, isNot(originalPosition));
    expect(model().active, isFalse);
    expect(model().selected, isFalse);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsNothing);

    await tester.tap(find.byType(ShapeElementView));
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
    await tester.tap(find.byType(ShapeElementView));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(model().active, isTrue);
    expect(model().selected, isTrue);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byType(ShapeElementView));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(model().active, isTrue);
    expect(model().selected, isFalse);
    expect(find.byKey(const ValueKey('shape-settings-panel')), findsOneWidget);

    await tester.tapAt(const Offset(40, 120));
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
