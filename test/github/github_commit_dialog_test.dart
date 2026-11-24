// Covers commit message validation and repeated dialog use.
// Exercises the dialog opened by the workspace GitHub workflow.

import 'package:elseplane/github/github_commit_dialog.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// ---------- Tests ----------

void main() {
  testWidgets('commit dialog validates text and survives immediate reopen', (tester) async {
    final results = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-commit'),
              onPressed: () async {
                results.add(
                  await showGitHubCommitDialog(
                    context,
                    repository: 'owner/repo',
                    branch: 'main',
                    newPath: 'canvas.canvas.json',
                  ),
                );
                setState(() {});
                results.add(
                  await showGitHubCommitDialog(
                    context,
                    repository: 'owner/repo',
                    branch: 'main',
                    newPath: 'canvas.canvas.json',
                  ),
                );
                setState(() {});
                results.add(
                  await showGitHubCommitDialog(
                    context,
                    repository: 'owner/repo',
                    branch: 'main',
                    newPath: 'canvas.canvas.json',
                  ),
                );
                setState(() {});
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-commit')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('github-commit-message'));
    expect(_fieldText(tester, field), '');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(find.text('A commit message is required.'), findsOneWidget);
    expect(field, findsOneWidget);
    expect(results, isEmpty);

    await tester.enterText(field, ' \n\t ');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(find.text('A commit message is required.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [null]);
    expect(_fieldText(tester, field), '');

    final message = '  Release: Save MixedCase Canvas\n${List.filled(80, 'x').join()}  ';
    await tester.enterText(field, message);
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(results, [null, message]);
    expect(_fieldText(tester, field), '');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [null, message, null]);
    expect(tester.takeException(), isNull);
  });
}

String _fieldText(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText))).controller.text;
