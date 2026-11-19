import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/github/github_panel.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('repository picker filters authorized repositories and selects by keyboard', (tester) async {
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-repository'),
              onPressed: () async => result = await showGitHubRepositoryDialog(
                context,
                repositories: [_repository(1, 'alpha', 'one'), _repository(2, 'beta', 'two')],
                installations: [_installation()],
                initialRepositoryId: null,
                onManageAccess: () async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-repository')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('github-repository-field')), findsNothing);
    expect(find.text('Choose a repository'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-use-repository'))).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('searchable-select-trigger')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('searchable-select-search'));
    await tester.enterText(search, 'beta');
    await tester.pumpAndSettle();
    expect(find.text('beta/two'), findsOneWidget);
    expect(find.text('alpha/one'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Public · default branch: main'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('github-use-repository')));
    await tester.pumpAndSettle();
    expect(result, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repository setup cancel and inaccessible choice do not confirm', (tester) async {
    int? result = 99;
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showGitHubRepositoryDialog(
                context,
                repositories: [_repository(1, 'alpha', 'one', canPull: false)],
                installations: [_installation()],
                initialRepositoryId: 1,
                onManageAccess: () async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('This repository does not have Contents read access through its installation.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-use-repository'))).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('access chooser opens a selected installation or offers another account', (tester) async {
    Uri? result;
    final installations = [
      _installation(),
      GitHubInstallation(
        id: 24,
        accountId: 8,
        accountLogin: 'organization',
        managementUri: Uri.parse('https://github.com/organizations/organization/settings/installations/24'),
        contentsPermission: 'write',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showGitHubAccessDialog(
                context,
                installations: installations,
                installUri: Uri.parse('https://github.com/apps/test-app/installations/new'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Manage owner'), findsOneWidget);
    expect(find.text('Manage organization'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('github-install-another-account')));
    await tester.pumpAndSettle();
    expect(result, Uri.parse('https://github.com/apps/test-app/installations/new'));
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

GitHubInstallation _installation() => GitHubInstallation(
  id: 23,
  accountId: 7,
  accountLogin: 'owner',
  managementUri: Uri.parse('https://github.com/settings/installations/23'),
  contentsPermission: 'write',
);

GitHubRepository _repository(int id, String owner, String name, {bool canPull = true}) => GitHubRepository(
  installationId: 23,
  id: id,
  owner: owner,
  name: name,
  isPrivate: false,
  defaultBranch: 'main',
  canPull: canPull,
  canPush: true,
  archived: false,
  disabled: false,
);

String _fieldText(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText))).controller.text;
