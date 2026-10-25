// Verifies that lazy view removal preserves independent animated scroll offsets.
// Exercises the controller through Flutter scrollable attachment and remounting.

import 'package:elseplane/ui/common/retained_scroll_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retains each axis across removal and clamps shorter content', (tester) async {
    final vertical = RetainedScrollController();
    final horizontal = RetainedScrollController();
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);

    Widget content({double extent = 2000}) => MaterialApp(
      home: SizedBox.expand(
        child: SingleChildScrollView(
          controller: vertical,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: extent, height: extent),
          ),
        ),
      ),
    );
    await tester.pumpWidget(content());
    vertical.jumpTo(170);
    horizontal.jumpTo(230);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(content());
    expect(vertical.offset, 170);
    expect(horizontal.offset, 230);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(content(extent: 100));
    await tester.pumpAndSettle();
    expect(vertical.offset, 0);
    expect(horizontal.offset, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
