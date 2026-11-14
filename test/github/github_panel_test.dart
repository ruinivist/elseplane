import 'package:elseplane/github/github_panel.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('repository dialog validates, trims, and survives immediate reopen', (tester) async {
    final results = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-repository'),
              onPressed: () async {
                results.add(await showGitHubRepositoryDialog(context, initial: 'first/repo'));
                setState(() {});
                results.add(await showGitHubRepositoryDialog(context, initial: 'second/repo'));
                setState(() {});
                results.add(await showGitHubRepositoryDialog(context, initial: 'third/repo'));
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-repository')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('github-repository-field'));
    expect(_fieldText(tester, field), 'first/repo');

    await tester.enterText(field, 'invalid');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter owner/repository'), findsOneWidget);
    expect(field, findsOneWidget);
    expect(results, isEmpty);

    await tester.enterText(field, ' owner/repo ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_fieldText(tester, field), 'second/repo');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_fieldText(tester, field), 'third/repo');
    expect(tester.takeException(), isNull);

    await tester.enterText(field, ' third/repo ');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(results, ['owner/repo', null, 'third/repo']);
    expect(tester.takeException(), isNull);
  });

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
                    isValidMessage: (message) => message.startsWith('docs:') && message.length <= 72,
                  ),
                );
                setState(() {});
                results.add(
                  await showGitHubCommitDialog(
                    context,
                    repository: 'owner/repo',
                    branch: 'main',
                    newPath: 'canvas.canvas.json',
                    isValidMessage: (message) => message.startsWith('docs:') && message.length <= 72,
                  ),
                );
                setState(() {});
                results.add(
                  await showGitHubCommitDialog(
                    context,
                    repository: 'owner/repo',
                    branch: 'main',
                    newPath: 'canvas.canvas.json',
                    isValidMessage: (message) => message.startsWith('docs:') && message.length <= 72,
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
