// Verifies native keyboard and disabled behavior of the raised icon action.

import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/surface_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('raised icon actions retain focus, keyboard activation, and disabled semantics', (tester) async {
    var calls = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Row(
            children: [
              SurfaceIconButton(icon: const Icon(Icons.add), tooltip: 'Add', onPressed: () => calls++),
              const SurfaceIconButton(icon: Icon(Icons.close), tooltip: 'Unavailable', onPressed: null),
              TextButton(onPressed: () {}, child: const Text('Next')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unavailable'));
    expect(calls, 0);
    final disabled = tester.getSemantics(find.byTooltip('Unavailable'));
    expect(disabled.flagsCollection.isEnabled.toBoolOrNull(), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byTooltip('Add')).flagsCollection.isFocused.toBoolOrNull(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('Next')).flagsCollection.isFocused.toBoolOrNull(), isTrue);
    semantics.dispose();
  });
}
