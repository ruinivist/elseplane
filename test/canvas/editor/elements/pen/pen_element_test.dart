// Verifies persisted pen interaction, options, and ink selection.

import 'package:elseplane/app/app.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../../../test_helpers.dart';

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    final preferences = SharedPreferencesAsync();
    await preferences.remove(PreferencesLibraryStore.libraryKey);
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
      of: find.byKey(const ValueKey('stroke-width-slider')),
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
              of: find.byKey(const ValueKey('stroke-width-slider')),
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

    await placeCodeBlock(tester, const Offset(120, 140));
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
}
