// Covers commit message validation and repeated dialog use.
// Exercises the dialog opened by the workspace GitHub workflow.

import 'package:elseplane/github/github_commit_dialog.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Tests ----------

void main() {
  testWidgets('commit dialog validates latest text and survives immediate reopen', (tester) async {
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
    expect(_fieldText(tester, field), 'docs: save canvas');
    expect(tester.widget<TextField>(find.descendant(of: field, matching: find.byType(TextField))).maxLength, 72);

    await tester.enterText(field, 'Not conventional');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(find.text('Use a lowercase Conventional Commit subject (72 characters max).'), findsOneWidget);
    expect(field, findsOneWidget);
    expect(results, isEmpty);

    await tester.enterText(field, 'docs: latest canvas');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(_fieldText(tester, field), 'docs: save canvas');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_fieldText(tester, field), 'docs: save canvas');
    expect(tester.takeException(), isNull);

    await tester.enterText(field, 'docs: reopened canvas');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(results, ['docs: latest canvas', null, 'docs: reopened canvas']);
    expect(tester.takeException(), isNull);
  });
}

String _fieldText(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText))).controller.text;
