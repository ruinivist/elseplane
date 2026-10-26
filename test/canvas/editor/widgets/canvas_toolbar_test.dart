// Verifies canvas toolbar actions and responsive placement.

import 'package:elseplane/app/app.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

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
      find.byKey(const ValueKey('settings-button')),
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
}
