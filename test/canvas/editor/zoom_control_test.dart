// Verifies the canvas zoom control's reveal and scale behavior.
// Exercises the viewport control against the real lazy canvas controller.

import 'package:elseplane/canvas/editor/widgets/zoom_control.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

// ---------- Tests ----------

void main() {
  testWidgets('reveals controls and changes or resets zoom', (tester) async {
    final controller = LazyCanvasController(minScale: 0.5, maxScale: 2);
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Stack(
            children: [
              LazyCanvas(controller: controller),
              Align(
                alignment: Alignment.bottomRight,
                child: ZoomControl(controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('100%'), findsOneWidget);
    expect(find.byKey(const ValueKey('zoom-out')).hitTestable(), findsNothing);
    expect(find.bySemanticsLabel('Reset zoom to 100%'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('zoom-control'))),
      tester.getSize(find.byKey(const ValueKey('zoom-reset'))),
    );

    controller.updateScalebyDelta(0.2);
    await tester.pump();
    expect(find.text('120%'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('120%')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('zoom-out')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('zoom-in')).hitTestable(), findsOneWidget);
    final out = tester.getRect(find.byKey(const ValueKey('zoom-out')));
    final reset = tester.getRect(find.byKey(const ValueKey('zoom-reset')));
    final zoomIn = tester.getRect(find.byKey(const ValueKey('zoom-in')));
    expect(out.right, lessThanOrEqualTo(reset.left));
    expect(reset.right, lessThanOrEqualTo(zoomIn.left));
    expect(_semanticsLabel('Zoom out'), findsOneWidget);
    expect(_semanticsLabel('Zoom in'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('zoom-out')));
    await tester.pump();
    expect(controller.scale, closeTo(1.1, 0.0001));

    await tester.tap(find.byKey(const ValueKey('zoom-in')));
    await tester.pump();
    expect(controller.scale, closeTo(1.2, 0.0001));

    await tester.tap(find.byKey(const ValueKey('zoom-reset')));
    await tester.pump();
    expect(controller.scale, 1);
    expect(find.text('100%'), findsOneWidget);

    controller.updateScalebyDelta(0.99);
    await tester.tap(find.byKey(const ValueKey('zoom-in')));
    await tester.tap(find.byKey(const ValueKey('zoom-in')));
    expect(controller.scale, 2);

    controller.updateScalebyDelta(-1.49);
    await tester.tap(find.byKey(const ValueKey('zoom-out')));
    await tester.tap(find.byKey(const ValueKey('zoom-out')));
    expect(controller.scale, 0.5);

    controller.updateScalebyDelta(10);
    expect(controller.scale, 2);
    controller.updateScalebyDelta(-10);
    expect(controller.scale, 0.5);

    await mouse.moveTo(Offset.zero);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zoom-in')).hitTestable(), findsNothing);

    controller.updateScalebyDelta(0.95);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zoom-in')).hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.scale, 1);
    semantics.dispose();
  });
}

Finder _semanticsLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);
