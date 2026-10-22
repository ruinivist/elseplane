// Verifies language-picker pointer ownership beyond code block bounds.
// Exercises search, selection, and dismissal through the full canvas.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('language popup owns $kind clicks outside the code block', (tester) async {
      const source = 'final value = 1;';
      await pumpCanvas(
        tester,
        TestLibraryStore(
          CanvasDocument(
            background: CanvasBackgroundKind.plain,
            elements: [
              CodeElementData(
                id: 'code',
                position: const Offset(180, 220),
                size: const Size(280, 240),
                language: CodeLanguage.dart,
                source: source,
                title: 'Example',
                showLineNumbers: true,
              ),
            ],
          ),
        ),
      );
      final model = tester.widget<CodeTool>(find.byType(CodeTool)).model;
      final trigger = find.byKey(const ValueKey('searchable-select-trigger'));
      final search = find.byKey(const ValueKey('searchable-select-search'));

      Future<void> click(Offset position) async {
        final pointer = await tester.startGesture(position, kind: kind);
        await pointer.up();
        await tester.pumpAndSettle();
      }

      Offset outsideBlock(Finder target) {
        final bounds = tester.getRect(target);
        final position = Offset(bounds.right - 12, bounds.center.dy);
        expect(tester.getRect(find.byType(CodeTool)).contains(position), isFalse);
        return position;
      }

      await click(tester.getCenter(find.byKey(const ValueKey('code-block-surface'))));
      expect(model.active, isTrue);
      await click(tester.getCenter(trigger));
      expect(search, findsOneWidget);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);

      await click(outsideBlock(search));
      expect(model.active, isTrue);
      expect(search, findsOneWidget);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.enterText(search, 'no matching language');
      await tester.pumpAndSettle();
      expect(find.text('No results'), findsOneWidget);
      await click(outsideBlock(find.text('No results')));
      expect(model.active, isTrue);
      expect(search, findsOneWidget);

      await click(outsideBlock(search));
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.enterText(search, 'pyth');
      await tester.pumpAndSettle();
      final results = find.byType(MenuItemButton);
      expect(results, findsOneWidget);
      expect(find.descendant(of: results, matching: find.text('Python')), findsOneWidget);
      expect(model.controller.text, source);
      expect(model.data.source, source);
      expect(model.language, CodeLanguage.dart);

      await click(outsideBlock(results));
      expect(model.language, CodeLanguage.python);
      expect(model.active, isTrue);
      expect(search, findsNothing);
      expect(model.controller.text, source);

      await click(tester.getCenter(trigger));
      expect(search, findsOneWidget);
      await click(const Offset(700, 500));
      expect(search, findsNothing);
      expect(model.active, isFalse);

      await click(tester.getCenter(find.byKey(const ValueKey('code-block-surface'))));
      await click(tester.getCenter(trigger));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      expect(model.active, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(model.active, isFalse);
      expect(model.controller.text, source);
    });
  }
}
