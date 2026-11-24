// Verifies mouse and keyboard canvas navigation.


import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

void main() {
  group('pointer navigation', () {
    setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

    testWidgets('right and middle drag pan over block controls', (tester) async {
      await tester.pumpWidget(testElseplaneApp());
      await tester.pump();
      await placeCodeBlock(tester, const Offset(120, 140));

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
      await tester.pumpWidget(testElseplaneApp());
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
      await tester.pumpWidget(testElseplaneApp());
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.byKey(const ValueKey('pen-preview')), findsOneWidget);
      await tester.dragFrom(
        const Offset(100, 200),
        const Offset(80, 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.byType(PenElementView), findsNothing);

      await tester.dragFrom(
        const Offset(100, 200),
        const Offset(80, 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(find.byType(PenElementView), findsOneWidget);
    });
  });
}
