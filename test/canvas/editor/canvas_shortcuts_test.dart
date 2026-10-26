// Verifies tool shortcuts and editing handoff.

import 'package:elseplane/app/app.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/widgets/canvas_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

void main() {
  setUp(() async {
    SharedPreferencesAsyncWeb.registerWith(null);
    final preferences = SharedPreferencesAsync();
    await preferences.remove(PreferencesLibraryStore.libraryKey);
  });

  testWidgets('keyboard shortcuts toggle tools and escape disables them', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    const shortcuts = [
      (LogicalKeyboardKey.keyT, 'text'),
      (LogicalKeyboardKey.keyC, 'code'),
      (LogicalKeyboardKey.keyS, 'shape'),
      (LogicalKeyboardKey.keyP, 'draw'),
      (LogicalKeyboardKey.keyE, 'erase'),
      (LogicalKeyboardKey.keyA, 'arrow'),
    ];
    for (final (key, name) in shortcuts) {
      final button = find.byKey(ValueKey('toolbar-$name'));
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(tester.widget<ToolbarButton>(button).selected, isTrue);

      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(tester.widget<ToolbarButton>(button).selected, isFalse);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected,
      isFalse,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected,
      isFalse,
    );
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.tapAt(const Offset(100, 160));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('text-markdown-editor')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(
      tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected,
      isFalse,
    );
    FocusManager.instance.primaryFocus?.unfocus();
  });

  testWidgets('enabling pen stops text editing', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 200));
    await tester.pump();
    await tester.pump();

    final model = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    expect(model.editing, isTrue);
    expect(find.byType(ElementTransformControls), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(model.editing, isFalse);
    expect(find.byType(ElementTransformControls), findsNothing);
  });
}
