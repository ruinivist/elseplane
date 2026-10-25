// Verifies the tool panel's pointer scroll boundary for short and long content.

import 'package:elseplane/canvas/editor/widgets/tool_options.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final height in [60.0, 800.0]) {
    testWidgets('tool options contain scrolling with content height $height', (tester) async {
      var ancestorScrolls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: starlessLightThemeData,
          home: Scaffold(
            body: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(event, (_) => ancestorScrolls++);
                }
              },
              child: Center(
                child: SizedBox(
                  width: ToolOptions.outerWidth,
                  height: 240,
                  child: ToolOptions(child: SizedBox(height: height)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable);
      final position = tester.state<ScrollableState>(scrollable).position;
      final point = tester.getCenter(scrollable);
      Future<void> wheel(Offset point, Offset delta) async {
        await tester.sendEventToBinding(PointerScrollEvent(position: point, scrollDelta: delta));
        await tester.pumpAndSettle();
      }

      await wheel(point, const Offset(0, -60));
      expect(position.pixels, position.minScrollExtent);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await wheel(point, const Offset(0, 60));
      expect(position.pixels, position.maxScrollExtent);
      await wheel(point, const Offset(60, 0));
      await wheel(
        tester.getTopLeft(scrollable) + Offset(tester.getSize(scrollable).width / 2, 2),
        const Offset(0, 60),
      );
      await wheel(point, const Offset(0, -60));
      if (height > 240) expect(position.pixels, lessThan(position.maxScrollExtent));
      expect(ancestorScrolls, 0);
      await wheel(const Offset(10, 10), const Offset(0, 60));
      expect(ancestorScrolls, 1);
    });
  }
}
