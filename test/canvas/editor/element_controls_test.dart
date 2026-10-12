// Verifies the Delete tooltip on shared canvas element controls.
// Covers mouse hover, dismissal, and deletion through the transform overlay.

import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  testWidgets('Delete shows on hover, dismisses on exit, and retains its action', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Center(
            child: ElementTransformControls(
              elementName: 'text',
              rotation: 0,
              onMove: (_) {},
              onRotate: (_) {},
              onDelete: () => deleted = true,
              onArrange: (_) {},
              onTransformStart: () {},
              onTransformEnd: () {},
              rotationCenter: () => Offset.zero,
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Delete')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(deleted, isFalse);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    await mouse.removePointer();
    await tester.tap(find.byKey(const ValueKey('text-block-delete-control')));
    expect(deleted, isTrue);
  });
}
