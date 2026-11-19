import 'dart:async';
import 'dart:convert';

import 'package:elseplane/app/workspace.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/github/github_panel.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../canvas/test_helpers.dart';

const _head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _tree = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _documentBlob = 'cccccccccccccccccccccccccccccccccccccccc';
const _nextTree = 'dddddddddddddddddddddddddddddddddddddddd';
const _nextCommit = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _destination = GitHubDestination(
  accountId: 7,
  repositoryId: 13,
  owner: 'owner',
  repository: 'repo',
  branch: 'main',
);

void main() {
  testWidgets('hides GitHub actions when no API is configured', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document('saved')));

    expect(find.byKey(const ValueKey('github-connect')), findsNothing);
  });

  testWidgets('restores the GitHub account after consuming the completion marker', (tester) async {
    var completionChecks = 0;
    final api = _commitApi(
      accountId: 17,
      accountLogin: 'canvas-user',
      github: (_) async => _json({'error': 'not found'}, status: 404),
    );
    await _pumpWorkspace(
      tester,
      TestLibraryStore(_document('saved')),
      api,
      navigate: (_) {},
      consumeCompletion: () {
        completionChecks++;
        return true;
      },
    );
    final useRepositoryButton = find.byKey(const ValueKey('github-use-repository'));
    await _pumpUntilBusySafe(
      tester,
      () =>
          useRepositoryButton.evaluate().isNotEmpty &&
          tester.widget<ButtonStyleButton>(useRepositoryButton).onPressed != null,
      'repository setup after GitHub completion',
    );

    expect(completionChecks, 1);
    expect(find.text('@canvas-user'), findsOneWidget);
    expect(find.byKey(const ValueKey('github-connect')), findsNothing);
    expect(useRepositoryButton, findsOneWidget);
    await _tapVisible(tester, find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('an expired GitHub operation exposes Connect and preserves local work', (tester) async {
    final document = _document('saved');
    final store = TestLibraryStore(document)
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'local', name: 'Physics', document: document)],
        currentId: 'local',
        githubDestination: _destination,
      );
    final requests = <String>[];
    final api = _commitApi(
      github: (request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({'message': 'private response'}, status: 401);
        }
        return _json({'message': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    final importButton = find.byKey(const ValueKey('github-import'));
    await _waitForEnabledButton(tester, importButton);

    await _tapVisible(tester, importButton);
    await pumpUntil(tester, () => find.byKey(const ValueKey('github-connect')).evaluate().isNotEmpty);

    expect(requests, contains('GET /repos/owner/repo/git/ref/heads/main'));
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('github-connect'))).onPressed, isNotNull);
    expect(find.textContaining('Reconnect GitHub to continue.').evaluate(), isNotEmpty);
    expect(find.textContaining('private response'), findsNothing);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());
    expect(store.library.current.document?.elements.whereType<TextElementData>().single.markdown, 'saved');
  });

  testWidgets('failed discovery keeps the saved destination and can be retried', (tester) async {
    final store = TestLibraryStore(_document('saved'))
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'local', name: 'Physics', document: _document('saved'))],
        currentId: 'local',
        githubDestination: _destination,
      );
    final api = _commitApi(
      failDiscoveryCount: 1,
      github: (_) async => _json({'error': 'not found'}, status: 404),
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await pumpUntil(tester, () => find.textContaining('temporarily unavailable').evaluate().isNotEmpty);

    expect(find.text('@owner'), findsOneWidget);
    expect(find.text('owner/repo'), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-commit'))).onPressed, isNull);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('github-repository'))).onPressed, isNull);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());

    final refreshButton = find.byKey(const ValueKey('github-refresh-repositories'));
    await _waitForEnabledButton(tester, refreshButton);
    await _tapVisible(tester, refreshButton);
    await pumpUntil(
      tester,
      () => tester.widget<FilledButton>(find.byKey(const ValueKey('github-commit'))).onPressed != null,
    );
    expect(find.text('owner/repo'), findsOneWidget);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());
  });

  testWidgets('read-only installation allows import but disables commit', (tester) async {
    final store = TestLibraryStore(_document('saved'))
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'local', name: 'Physics', document: _document('saved'))],
        currentId: 'local',
        githubDestination: _destination,
      );
    final api = _commitApi(
      installations: [_installation(permission: 'read')],
      repositories: [_repositoryJson(canPush: false)],
      github: (_) async => _json({'error': 'not found'}, status: 404),
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    final importButton = find.byKey(const ValueKey('github-import'));
    await _waitForEnabledButton(tester, importButton);

    expect(tester.widget<TextButton>(importButton).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-commit'))).onPressed, isNull);
    expect(find.textContaining('read-only'), findsOneWidget);
  });

  testWidgets('manage access installs the app when there are no installations', (tester) async {
    Uri? opened;
    final api = _commitApi(
      installations: const [],
      repositories: const [],
      github: (_) async => _json({'error': 'not found'}, status: 404),
    );
    await _pumpWorkspace(
      tester,
      TestLibraryStore(_document('saved')),
      api,
      navigate: (_) {},
      open: (url) => opened = Uri.parse(url),
    );
    final manageButton = find.byKey(const ValueKey('github-manage-access'));
    await _waitForEnabledButton(tester, manageButton);
    await _tapVisible(tester, manageButton);
    await pumpUntil(tester, () => opened != null);
    expect(opened, Uri.parse('https://github.com/apps/test-app/installations/new'));
  });

  testWidgets('repository cancellation and failed save preserve the previous choice', (tester) async {
    final store = _FailingLibraryStore(_document('saved'))
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'local', name: 'Physics', document: _document('saved'))],
        currentId: 'local',
        githubDestination: _destination,
      );
    final api = _commitApi(
      github: (request) async {
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          store.failSaves = true;
          return _json({
            'object': {'type': 'commit', 'sha': _head},
          });
        }
        return _json({'error': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await _waitForEnabledButton(tester, find.byKey(const ValueKey('github-import')));

    final repositoryButton = find.byKey(const ValueKey('github-repository'));
    await _waitForEnabledButton(tester, repositoryButton);
    await _tapVisible(tester, repositoryButton);
    await _pumpUntilBusySafe(
      tester,
      () => find.byKey(const ValueKey('github-repository-select')).evaluate().isNotEmpty,
      'repository picker',
    );
    await _tapVisible(tester, find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.library.githubDestination?.toJson(), _destination.toJson());
    expect(store.persisted, isNull);

    await _tapVisible(tester, repositoryButton);
    await _pumpUntilBusySafe(
      tester,
      () => find.byKey(const ValueKey('github-repository-select')).evaluate().isNotEmpty,
      'repository picker reopened',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('github-use-repository')));
    await pumpUntil(tester, () => find.textContaining('storage unavailable').evaluate().isNotEmpty);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());
    store.failSaves = false;
  });

  testWidgets('imports the whole selected repository through the workspace coordinator', (tester) async {
    final local = _document('Local');
    final remote = _document('Remote');
    final remoteBytes = utf8.encode(jsonEncode(remote.toJson()));
    final store = TestLibraryStore(local)
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'local', name: 'Local', document: local)],
        currentId: 'local',
        githubDestination: _destination,
      );
    final requests = <String>[];
    final api = _commitApi(
      requests: requests,
      github: (request) async {
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({
            'object': {'type': 'commit', 'sha': _head},
          });
        }
        if (request.url.path.endsWith('/git/commits/$_head')) {
          return _json({
            'tree': {'sha': _tree},
          });
        }
        if (request.url.path.endsWith('/git/trees/$_tree')) {
          return _json({
            'truncated': false,
            'tree': [
              _treeEntry('University/Physics.canvas.json', _documentBlob, remoteBytes.length),
              _treeEntry('README.md', _nextCommit, 7),
            ],
          });
        }
        if (request.url.path.endsWith('/git/blobs/$_documentBlob')) {
          return _json({
            'sha': _documentBlob,
            'size': remoteBytes.length,
            'encoding': 'base64',
            'content': base64Encode(remoteBytes),
          });
        }
        return _json({'error': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    final importButton = find.byKey(const ValueKey('github-import'));
    await _waitForEnabledButton(tester, importButton);

    await _tapVisible(tester, importButton);
    await _pumpUntilBusySafe(
      tester,
      () => find.text('Import result').evaluate().isNotEmpty,
      'repository import result',
    );

    expect(requests, contains('GET /repos/owner/repo/git/blobs/$_documentBlob'));
    expect(
      requests.where((request) => request == 'GET /user/installations/23/repositories').length,
      greaterThanOrEqualTo(2),
    );
    expect(requests.where((request) => request.contains('/git/blobs/')), hasLength(1));
    expect(find.byKey(const ValueKey('github-canvas-University/Physics.canvas.json')), findsNothing);
    expect(store.library.currentId, 'local');
    expect(store.library.current.document?.elements.whereType<TextElementData>().single.markdown, 'Local');
    final folder = store.library.files.singleWhere((file) => file.name == 'University' && file.isFolder);
    final imported = store.library.files.singleWhere((file) => file.parentId == folder.id && file.name == 'Physics');
    expect(imported.document?.elements.whereType<TextElementData>().single.markdown, 'Remote');
    expect(store.library.githubDestination?.toJson(), _destination.toJson());

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  testWidgets('changing repositories preserves local documents without tracking warnings', (tester) async {
    final document = _document('preserved');
    final store = TestLibraryStore(document)
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'local', name: 'Physics', document: document)],
        currentId: 'local',
        githubDestination: _destination,
      );
    final api = _commitApi(
      accountId: 17,
      accountLogin: 'new-owner',
      github: (request) async {
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({
            'object': {'type': 'commit', 'sha': _head},
          });
        }
        return _json({'error': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    final repositoryButton = find.byKey(const ValueKey('github-repository'));
    await _pumpUntilBusySafe(
      tester,
      () => repositoryButton.evaluate().isNotEmpty && tester.widget<TextButton>(repositoryButton).onPressed != null,
      'repository discovery',
    );
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      ScaffoldMessenger.of(tester.element(repositoryButton)).hideCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    await _tapVisible(tester, repositoryButton);
    await _pumpUntilBusySafe(
      tester,
      () => find.byKey(const ValueKey('github-repository-select')).evaluate().isNotEmpty,
      'repository picker',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('searchable-select-trigger')));
    await _pumpUntilBusySafe(
      tester,
      () => find.byKey(const ValueKey('searchable-select-search')).evaluate().isNotEmpty,
      'repository search',
    );
    await tester.enterText(find.byKey(const ValueKey('searchable-select-search')), 'owner/repo');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('searchable-select-trigger')),
              matching: find.byType(Text),
            ),
          )
          .data,
      'owner/repo',
    );
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-use-repository'))).onPressed, isNotNull);
    await _tapVisible(tester, find.byKey(const ValueKey('github-use-repository')));
    await _pumpUntilBusySafe(
      tester,
      () => store.library.githubDestination?.accountId == 17,
      'destination save',
    );
    expect(find.textContaining('clears saved GitHub links'), findsNothing);

    expect(store.library.current.document, same(document));
    expect(store.library.files, hasLength(1));
    expect(store.library.current.name, 'Physics');
  });

  testWidgets('repository picker remains usable in a short viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showGitHubRepositoryDialog(
                context,
                repositories: [_repositoryRecord()],
                installations: [_installationRecord()],
                initialRepositoryId: 13,
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
    final trigger = find.byKey(const ValueKey('searchable-select-trigger'));
    expect(trigger.hitTestable(), findsOneWidget);
    final useRepository = find.text('Use repository');
    await tester.ensureVisible(useRepository);
    await tester.pumpAndSettle();
    expect(useRepository.hitTestable(), findsOneWidget);
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('searchable-select-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace interlock rejects duplicate GitHub operations', (tester) async {
    final response = Completer<http.Response>();
    final requests = <String>[];
    Uri? navigation;
    final api = _api(
      mediator: (request) {
        if (request.url.path == '/oauth/github/token') {
          return Future.value(_json({'error': 'no session'}, status: 401));
        }
        requests.add(request.url.path);
        return response.future;
      },
    );
    await _pumpWorkspace(tester, TestLibraryStore(_document('saved')), api, navigate: (uri) => navigation = uri);

    final connectButton = find.byKey(const ValueKey('github-connect'));
    await _waitForEnabledButton(tester, connectButton);
    final connect = tester.widget<TextButton>(connectButton).onPressed!;
    await _tapVisible(tester, connectButton);
    await _pumpUntilBusySafe(tester, () => requests.isNotEmpty, 'GitHub authorization request');
    connect();
    await tester.pump();
    expect(requests, ['/oauth/github/start']);

    response.complete(_json({'authorization_url': 'https://github.com/login/oauth/authorize?client_id=app'}));
    await _pumpUntilBusySafe(tester, () => navigation != null, 'authorization navigation');
    expect(navigation?.host, 'github.com');
  });

  testWidgets('failed completed-edit save prevents authorization navigation', (tester) async {
    final store = _FailingLibraryStore(_document('before'));
    var mediatorRequests = 0;
    var navigations = 0;
    final api = _api(
      mediator: (request) async {
        if (request.url.path == '/oauth/github/token') return _json({'error': 'no session'}, status: 401);
        mediatorRequests++;
        return _json({'authorization_url': 'https://github.com/login/oauth/authorize?client_id=app'});
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) => navigations++);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' unsaved');
    await tester.pump();
    store.failSaves = true;

    final connectButton = find.byKey(const ValueKey('github-connect'));
    await _waitForEnabledButton(tester, connectButton);
    await _tapVisible(tester, connectButton);
    await _pumpUntilBusySafe(
      tester,
      () => find.text('Could not save canvas. GitHub authorization was not started.').evaluate().isNotEmpty,
      'failed authorization save message',
    );

    expect(mediatorRequests, 0);
    expect(navigations, 0);
    expect(find.text('Could not save canvas. GitHub authorization was not started.'), findsOneWidget);
    expect(tester.widget<TextElementView>(find.byType(TextElementView)).resources.node.markdown, 'before unsaved');
    store.failSaves = false;
  });

  testWidgets('saves completed edits before starting authorization', (tester) async {
    final store = TestLibraryStore(_document('before'));
    var mediatorRequests = 0;
    Uri? navigation;
    final api = _api(
      mediator: (request) async {
        if (request.url.path == '/oauth/github/token') return _json({'error': 'no session'}, status: 401);
        mediatorRequests++;
        return _json({'authorization_url': 'https://github.com/login/oauth/authorize?client_id=app'});
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (uri) => navigation = uri);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' after');
    await tester.pump();

    final connectButton = find.byKey(const ValueKey('github-connect'));
    await _waitForEnabledButton(tester, connectButton);
    await _tapVisible(tester, connectButton);
    await _pumpUntilBusySafe(tester, () => navigation != null, 'authorization navigation');

    expect(store.persisted, isNotNull);
    expect(store.persisted!.elements.whereType<TextElementData>().single.markdown, 'before after');
    expect(mediatorRequests, 1);
    expect(navigation?.host, 'github.com');
  });

  testWidgets('commits a captured current-canvas tree without local tracking writes', (tester) async {
    final document = _document('Maths');
    final current = CanvasFile(id: 'current', name: 'Maths', document: document);
    final store = TestLibraryStore(document)
      ..library = CanvasLibrary(
        files: [
          current,
          CanvasFile(id: 'other', name: 'Physics', document: _document('other')),
        ],
        currentId: current.id,
        githubDestination: _destination,
      );
    final requests = <String>[];
    final blobBodies = <Map<String, Object?>>[];
    late Map<String, Object?> treeBody;
    late Map<String, Object?> commitBody;
    final api = _commitApi(
      requests: requests,
      github: (request) async {
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({
            'object': {'type': 'commit', 'sha': _head},
          });
        }
        if (request.url.path.endsWith('/git/commits/$_head')) {
          return _json({
            'tree': {'sha': _tree},
          });
        }
        if (request.url.path.endsWith('/git/trees/$_tree')) return _json({'truncated': false, 'tree': <Object?>[]});
        if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) {
          blobBodies.add(jsonDecode(request.body) as Map<String, Object?>);
          return _json({'sha': _documentBlob});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) {
          treeBody = jsonDecode(request.body) as Map<String, Object?>;
          return _json({'sha': _nextTree});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) {
          commitBody = jsonDecode(request.body) as Map<String, Object?>;
          return _json({'sha': _nextCommit, 'html_url': 'https://github.com/owner/repo/commit/$_nextCommit'});
        }
        if (request.method == 'PATCH') return _json({'ref': 'refs/heads/main'});
        if (request.url.path.contains('/git/blobs/')) fail('Commit must not fetch old blob contents');
        return _json({'error': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    final commitButton = find.byKey(const ValueKey('github-commit'));
    await _waitForEnabledButton(tester, commitButton);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' edited');
    await tester.pump();

    await _tapVisible(tester, commitButton);
    await _pumpUntilBusySafe(
      tester,
      () => find.byKey(const ValueKey('github-commit-message')).evaluate().isNotEmpty,
      'commit confirmation',
    );
    expect(find.byKey(const ValueKey('github-repository-select')), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Commit'));
    await _pumpUntilBusySafe(
      tester,
      () =>
          find.textContaining('Canvas committed to GitHub.').evaluate().isNotEmpty ||
          find.byType(SnackBar).evaluate().isNotEmpty,
      'commit result',
    );
    if (find.textContaining('Canvas committed to GitHub.').evaluate().isEmpty) {
      final message = (tester.widget<SnackBar>(find.byType(SnackBar)).content as Text).data;
      fail('Commit failed: $message; requests: ${requests.join(', ')}');
    }

    final uploaded =
        jsonDecode(utf8.decode(base64Decode(blobBodies.single['content']! as String))) as Map<String, Object?>;
    final uploadedElement = (uploaded['elements']! as List<Object?>).single! as Map<String, Object?>;
    final treeEntry = (treeBody['tree']! as List<Object?>).single! as Map<String, Object?>;
    expect(uploadedElement['markdown'], 'Maths edited');
    expect(treeEntry['path'], 'Maths.canvas.json');
    expect(treeBody['base_tree'], _tree);
    expect(commitBody['parents'], [_head]);
    expect(requests.where((request) => request.contains('/git/blobs/')), isEmpty);
    expect(
      requests.where((request) => request == 'GET /user/installations/23/repositories').length,
      greaterThanOrEqualTo(2),
    );
    expect(find.byKey(const ValueKey('github-repository-select')), findsNothing);
    expect(store.library.current.document?.elements.whereType<TextElementData>().single.markdown, 'Maths edited');
    expect(store.library.current.toJson().keys, isNot(contains('githubTracking')));
    expect(store.library.current.toJson().keys, isNot(contains('githubPendingTracking')));

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('uncertain commits leave a later explicit submission available', (tester) async {
    final document = _document('Maths');
    final store = TestLibraryStore(document)
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'current', name: 'Maths', document: document)],
        currentId: 'current',
        githubDestination: _destination,
      );
    var patches = 0;
    final api = _commitApi(
      github: (request) async {
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({
            'object': {'type': 'commit', 'sha': _head},
          });
        }
        if (request.url.path.endsWith('/git/commits/$_head')) {
          return _json({
            'tree': {'sha': _tree},
          });
        }
        if (request.url.path.endsWith('/git/trees/$_tree')) return _json({'truncated': false, 'tree': <Object?>[]});
        if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) return _json({'sha': _documentBlob});
        if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) return _json({'sha': _nextTree});
        if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) return _json({'sha': _nextCommit});
        if (request.method == 'PATCH') {
          patches++;
          return _json({'message': 'unknown'}, status: 500);
        }
        return _json({'error': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    final commitButton = find.byKey(const ValueKey('github-commit'));
    await _waitForEnabledButton(tester, commitButton);

    for (var attempt = 1; attempt <= 2; attempt++) {
      await _tapVisible(tester, commitButton);
      await _pumpUntilBusySafe(
        tester,
        () => find.byKey(const ValueKey('github-commit-message')).evaluate().isNotEmpty,
        'commit confirmation $attempt',
      );
      await tester.tap(find.text('Commit'));
      await _pumpUntilBusySafe(
        tester,
        () => find.textContaining('may have succeeded').evaluate().isNotEmpty,
        'uncertain result $attempt',
      );
      expect(find.textContaining('duplicate commit'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-commit'))).onPressed, isNotNull);
    }

    expect(patches, 2);
  });
}

Future<void> _pumpUntilBusySafe(WidgetTester tester, bool Function() done, String description) async {
  await tester.runAsync(() async {
    final elapsed = Stopwatch()..start();
    while (!done() && elapsed.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(Duration.zero);
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
  if (!done()) fail('Did not reach $description.');
}

Future<void> _waitForEnabledButton(WidgetTester tester, Finder finder) async {
  await pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty && tester.widget<ButtonStyleButton>(finder).onPressed != null,
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  LibraryStore store,
  GitHubApi api, {
  required void Function(Uri) navigate,
  void Function(String url)? open,
  bool Function()? consumeCompletion,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: starlessLightThemeData,
      home: Workspace(
        libraryStore: store,
        attachmentStore: TestAttachmentStore(),
        projectFiles: TestProjectFiles(),
        githubApi: api,
        githubAppSlug: 'test-app',
        navigateGitHubAuthorization: navigate,
        consumeGitHubCompletion: consumeCompletion ?? () => false,
        openGitHubLink: open ?? (_) {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

GitHubApi _api({
  Future<http.Response> Function(http.Request)? github,
  Future<http.Response> Function(http.Request)? mediator,
}) => GitHubApi(
  mediatorUrl: Uri.parse('https://mediator.example'),
  mediatorClient: MockClient(
    mediator ??
        (request) async => request.url.path == '/oauth/github/token'
            ? _json({'error': 'no session'}, status: 401)
            : _json({'error': 'not found'}, status: 404),
  ),
  githubClient: MockClient(github ?? (_) async => _json({'error': 'not found'}, status: 404)),
);

GitHubApi _commitApi({
  required Future<http.Response> Function(http.Request) github,
  int accountId = 7,
  String accountLogin = 'owner',
  List<Map<String, Object?>>? installations,
  List<Map<String, Object?>>? repositories,
  List<String>? requests,
  int failDiscoveryCount = 0,
}) {
  var failuresRemaining = failDiscoveryCount;
  return GitHubApi(
    mediatorUrl: Uri.parse('https://mediator.example'),
    mediatorClient: MockClient((request) async {
      if (request.url.path == '/oauth/github/token') return _json({'access_token': 'test-token'});
      return _json({'error': 'not found'}, status: 404);
    }),
    githubClient: MockClient((request) async {
      requests?.add('${request.method} ${request.url.path}');
      if (request.url.path == '/user') return _json({'id': accountId, 'login': accountLogin});
      if (request.url.path == '/user/installations') {
        if (failuresRemaining > 0) {
          failuresRemaining--;
          return _json({'message': 'temporary'}, status: 500);
        }
        final values = installations ?? [_installation()];
        return _json({'total_count': values.length, 'installations': values});
      }
      if (request.url.path == '/user/installations/23/repositories') {
        final values = repositories ?? [_repositoryJson()];
        return _json({'total_count': values.length, 'repositories': values});
      }
      return await github(request);
    }),
  );
}

CanvasDocument _document(String markdown) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    TextElementData(
      id: 'text',
      position: Offset.zero,
      width: 280,
      height: 100,
      markdown: markdown,
      style: const TextNodeStyle(fontFamily: 'ABeeZee', color: Color(0xff201c1a)),
    ),
  ],
);

Map<String, Object?> _treeEntry(String path, String sha, int size) => {
  'path': path,
  'sha': sha,
  'type': 'blob',
  'mode': '100644',
  'size': size,
};

GitHubInstallation _installationRecord({int id = 23, String permission = 'write'}) => GitHubInstallation(
  id: id,
  accountId: 7,
  accountLogin: 'owner',
  managementUri: Uri.parse('https://github.com/settings/installations/$id'),
  contentsPermission: permission,
);

GitHubRepository _repositoryRecord({bool canPull = true, bool canPush = true}) => GitHubRepository(
  installationId: 23,
  id: 13,
  owner: 'owner',
  name: 'repo',
  isPrivate: false,
  defaultBranch: 'main',
  canPull: canPull,
  canPush: canPush,
  archived: false,
  disabled: false,
);

Map<String, Object?> _installation({String permission = 'write'}) => {
  'id': 23,
  'account': {'id': 7, 'login': 'owner'},
  'html_url': 'https://github.com/settings/installations/23',
  'permissions': {'contents': permission},
};

Map<String, Object?> _repositoryJson({
  bool canPull = true,
  bool canPush = true,
  String defaultBranch = 'main',
}) => {
  'id': 13,
  'owner': {'login': 'owner'},
  'name': 'repo',
  'full_name': 'owner/repo',
  'private': false,
  'default_branch': defaultBranch,
  'permissions': {'pull': canPull, 'push': canPush},
  'archived': false,
  'disabled': false,
};

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json'},
);

class _FailingLibraryStore extends TestLibraryStore {
  _FailingLibraryStore(super.initial);

  bool failSaves = false;

  @override
  Future<void> save(CanvasLibrary snapshot) async {
    if (failSaves) throw StateError('storage unavailable');
    await super.save(snapshot);
  }
}
