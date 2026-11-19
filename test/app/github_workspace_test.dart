import 'dart:async';
import 'dart:convert';

import 'package:elseplane/app/workspace.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/select.dart';
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

    await _tapVisible(tester, find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    expect(find.text('Sync'), findsNothing);
    expect(find.byKey(const ValueKey('github-connect')), findsNothing);
  });

  testWidgets('returns to Sync and offers first import after an explicit selection', (tester) async {
    var completionChecks = 0;
    final store = TestLibraryStore(_document('saved'));
    final api = _commitApi(
      accountId: 17,
      accountLogin: 'canvas-user',
      github: (request) async =>
          request.url.path.endsWith('/git/ref/heads/main') ? _ref() : _json({'error': 'not found'}, status: 404),
    );
    await _pumpWorkspace(
      tester,
      store,
      api,
      navigate: (_) {},
      consumeCompletion: () {
        completionChecks++;
        return true;
      },
    );
    await _waitForRepositoryPicker(tester);
    expect(completionChecks, 1);
    expect(find.text('Connected as @canvas-user'), findsOneWidget);
    expect(find.text('Choose repository'), findsOneWidget);
    expect(find.text('Import canvases from repo?'), findsNothing);
    expect(store.library.githubDestination, isNull);
    await _selectRepository(tester, 'owner/repo');
    await pumpUntil(tester, () => find.text('Import canvases from repo?').evaluate().isNotEmpty);
    expect(find.text('Public · Default branch: main'), findsOneWidget);
    expect(store.library.githubDestination?.accountId, 17);
    expect(store.library.githubImportPromptPending, isTrue);

    await _tapVisible(tester, find.text('Skip'));
    await _waitForEnabledButton(tester, _importButton);
    expect(find.text('Import canvases from repo?'), findsNothing);
    expect(store.library.githubImportPromptPending, isFalse);
    await _closeSync(tester);
    expect(_marker, findsOneWidget);
    await _openSync(tester);
    expect(find.text('Import canvases from repo?'), findsNothing);
    expect(completionChecks, 1);
    await _tapVisible(tester, find.byKey(const ValueKey('searchable-select-trigger')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, 'owner/repo'), findsOneWidget);
    expect(find.text('Choose repository'), findsNothing);
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
    await _openSync(tester);
    final importButton = _importButton;
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
    await _openSync(tester);
    await pumpUntil(tester, () => find.textContaining('temporarily unavailable').evaluate().isNotEmpty);

    expect(find.text('Connected as @owner'), findsOneWidget);
    expect(find.text('owner/repo'), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(tester.widget<TextButton>(_importButton).onPressed, isNull);
    expect(tester.widget<SearchableSelect<int?>>(_repositoryPicker).onChanged, isNull);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());

    final refreshButton = find.byKey(const ValueKey('github-refresh-repositories'));
    expect(tester.widget<IconButton>(refreshButton).onPressed, isNotNull);
    await _tapVisible(tester, refreshButton);
    await _waitForEnabledButton(tester, _importButton);
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
    await _openSync(tester);
    final importButton = _importButton;
    await _waitForEnabledButton(tester, importButton);

    expect(tester.widget<TextButton>(importButton).onPressed, isNotNull);
    expect(find.textContaining('read-only'), findsOneWidget);
    await _closeSync(tester);
    expect(tester.widget<InkWell>(_marker).onTap, isNull);
    expect(tester.widget<TextButton>(_commitAction).onPressed, isNull);
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
    await _openSync(tester);
    final manageButton = find.byKey(const ValueKey('github-manage-access'));
    await _waitForEnabledButton(tester, manageButton);
    await _tapVisible(tester, manageButton);
    await pumpUntil(tester, () => opened != null);
    expect(opened, Uri.parse('https://github.com/apps/test-app/installations/new'));
  });

  testWidgets('invalid repository selection and a failed save preserve the previous choice', (tester) async {
    final store = _FailingLibraryStore(_document('saved'))
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'local', name: 'Physics', document: _document('saved'))],
        currentId: 'local',
        githubDestination: _destination,
      );
    final api = _commitApi(
      repositories: [
        _repositoryJson(),
        _repositoryJson(id: 14, name: 'private', canPull: false),
        _repositoryJson(id: 15, name: 'another'),
      ],
      github: (request) async {
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          store.failSaves = true;
          return _ref();
        }
        return _json({'error': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await _openSync(tester);
    await _selectRepository(tester, 'owner/private');
    await pumpUntil(tester, () => find.textContaining('requires Contents read access').evaluate().isNotEmpty);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());
    expect(store.persisted, isNull);

    await _selectRepository(tester, 'owner/another');
    await pumpUntil(tester, () => find.textContaining('Could not save the repository selection').evaluate().isNotEmpty);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());
    expect(find.text('owner/repo'), findsOneWidget);
    store.failSaves = false;
  });

  testWidgets('imports the whole selected repository through the workspace coordinator', (tester) async {
    final local = _document('Local');
    final remote = _document('Remote');
    final store = TestLibraryStore(local)
      ..library = CanvasLibrary(
        files: [CanvasFile(id: 'local', name: 'Local', document: local)],
        currentId: 'local',
        githubDestination: _destination,
      );
    final requests = <String>[];
    final api = _importApi('University/Physics.canvas.json', remote, requests: requests);
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await _openSync(tester);
    final importButton = _importButton;
    await _waitForEnabledButton(tester, importButton);

    await _tapVisible(tester, importButton);
    await _pumpUntilBusySafe(
      tester,
      () => find.textContaining('Imported 1 canvas.').evaluate().isNotEmpty,
      'repository import result',
    );

    expect(requests, contains('GET /repos/owner/repo/git/blobs/$_documentBlob'));
    expect(
      requests.where((request) => request == 'GET /user/installations/23/repositories').length,
      greaterThanOrEqualTo(2),
    );
    expect(requests.where((request) => request.contains('/git/blobs/')), hasLength(1));
    expect(find.textContaining('University/Physics.canvas.json'), findsOneWidget);
    expect(store.library.currentId, 'local');
    expect(store.library.current.document?.elements.whereType<TextElementData>().single.markdown, 'Local');
    final folder = store.library.files.singleWhere((file) => file.name == 'University' && file.isFolder);
    final imported = store.library.files.singleWhere((file) => file.parentId == folder.id && file.name == 'Physics');
    expect(imported.document?.elements.whereType<TextElementData>().single.markdown, 'Remote');
    expect(store.library.githubDestination?.toJson(), _destination.toJson());

    expect(imported.githubBaseline?.path, 'University/Physics.canvas.json');
    expect(store.library.current.githubBaseline, isNull);
  });

  testWidgets('first import dismisses the prompt and reviews overwrites inline', (tester) async {
    final store = _savedStore();
    store.library = CanvasLibrary(files: store.library.files, currentId: store.library.currentId);
    final remote = _document('Remote');
    final api = _importApi('Physics.canvas.json', remote);
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await _openSync(tester);
    await _selectRepository(tester, 'owner/repo');
    await _waitForEnabledButton(tester, _importButton);
    expect(find.text('Import canvases from repo?'), findsOneWidget);

    final review = find.text('Overwrite canvases?');
    await _tapVisible(tester, _importButton);
    await pumpUntil(tester, () => review.evaluate().isNotEmpty);
    expect(find.textContaining('Shared images may also change'), findsOneWidget);
    expect(find.text('Physics.canvas.json'), findsOneWidget);
    expect(store.library.githubImportPromptPending, isFalse);
    expect(store.library.current.githubBaseline, isNull);
    final beforeReview = store.library;
    await _tapVisible(tester, find.text('Cancel'));
    await pumpUntil(tester, () => find.text('Import canceled.').evaluate().isNotEmpty);
    expect(store.library, same(beforeReview));
    expect(find.text('Import canvases from repo?'), findsNothing);

    await _tapVisible(tester, _importButton);
    await pumpUntil(tester, () => review.evaluate().isNotEmpty);
    await _closeSync(tester);
    await _waitForMarkerAction(tester);
    expect(store.library, same(beforeReview));

    await _openSync(tester);
    await _tapVisible(tester, _importButton);
    await pumpUntil(tester, () => review.evaluate().isNotEmpty);
    await _tapVisible(tester, find.text('Overwrite and import'));
    await pumpUntil(tester, () => find.textContaining('Imported 1 canvas.').evaluate().isNotEmpty);
    expect(store.library.current.document, remote);
    expect(store.library.current.githubBaseline?.isFor(_destination), isTrue);
    await _closeSync(tester);
    expect(_marker, findsNothing);
    expect(tester.widget<TextElementView>(find.byType(TextElementView)).resources.node.markdown, 'Remote');
  });

  testWidgets('logout retries inline and the saved destination is reused after reconnect', (tester) async {
    final store = _savedStore();
    var attempts = 0;
    final api = _commitApi(
      github: (_) async => _json({'error': 'not found'}, status: 404),
      logout: () => ++attempts == 1 ? _json({'error': 'temporary'}, status: 500) : http.Response('', 204),
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await _openSync(tester);
    await _waitForRepositoryPicker(tester);
    await _tapVisible(tester, find.text('Log out'));
    final retry = find.widgetWithText(TextButton, 'Retry logout');
    await _waitForEnabledButton(tester, retry);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());
    await _tapVisible(tester, retry);
    await _waitForEnabledButton(tester, find.widgetWithText(TextButton, 'Connect GitHub'));
    expect(attempts, 2);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());

    await tester.pumpWidget(const SizedBox());
    await _pumpWorkspace(tester, store, api, navigate: (_) {}, consumeCompletion: () => true);
    await _waitForEnabledButton(tester, _importButton);
    expect(find.text('owner/repo'), findsOneWidget);
    expect(find.text('Import canvases from repo?'), findsNothing);
  });

  testWidgets('default branch changes require refresh and explicit reselection before importing', (tester) async {
    final store = _savedStore();
    final repositories = [_repositoryJson()];
    final api = _commitApi(
      repositories: repositories,
      github: (request) async =>
          request.url.path.endsWith('/git/ref/heads/next') ? _ref() : _json({'error': 'not found'}, status: 404),
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await _openSync(tester);
    await _waitForEnabledButton(tester, _importButton);
    repositories[0] = _repositoryJson(defaultBranch: 'next');
    await _tapVisible(tester, _importButton);
    await pumpUntil(tester, () => find.textContaining('Refresh and reselect').evaluate().isNotEmpty);
    expect(tester.widget<TextButton>(_importButton).onPressed, isNull);
    expect(tester.widget<SearchableSelect<int?>>(_repositoryPicker).onChanged, isNull);
    expect(store.library.githubDestination?.branch, 'main');

    await _tapVisible(tester, find.byTooltip('Refresh repositories'));
    await _waitForRepositoryPicker(tester);
    expect(find.textContaining('Default branch changed from main to next'), findsOneWidget);
    expect(tester.widget<TextButton>(_importButton).onPressed, isNull);
    expect(store.library.githubDestination?.branch, 'main');
    await _selectRepository(tester, 'owner/repo');
    await _waitForEnabledButton(tester, _importButton);
    expect(store.library.githubDestination?.branch, 'next');
  });

  testWidgets('Sync remains usable in a short dark viewport and shows installation choices inline', (tester) async {
    tester.view.physicalSize = const Size(360, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Uri? opened;
    await _pumpWorkspace(
      tester,
      _savedStore(),
      _commitApi(github: (_) async => _json({'error': 'not found'}, status: 404)),
      navigate: (_) {},
      open: (url) => opened = Uri.parse(url),
      theme: starlessDarkThemeData,
    );
    await _openSync(tester);
    await _waitForRepositoryPicker(tester);
    await _tapVisible(tester, find.byKey(const ValueKey('searchable-select-trigger')));
    await pumpUntil(tester, () => find.byKey(const ValueKey('searchable-select-search')).evaluate().isNotEmpty);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Manage GitHub access'));
    await tester.pump();
    await _tapVisible(tester, find.text('Manage owner'));
    await pumpUntil(tester, () => opened != null);
    expect(opened, Uri.parse('https://github.com/settings/installations/23'));
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

    await _openSync(tester);
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

    await _openSync(tester);
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

    await _openSync(tester);
    final connectButton = find.byKey(const ValueKey('github-connect'));
    await _waitForEnabledButton(tester, connectButton);
    await _tapVisible(tester, connectButton);
    await _pumpUntilBusySafe(tester, () => navigation != null, 'authorization navigation');

    expect(store.persisted, isNotNull);
    expect(store.persisted!.elements.whereType<TextElementData>().single.markdown, 'before after');
    expect(mediatorRequests, 1);
    expect(navigation?.host, 'github.com');
  });

  testWidgets('commits and records the captured canvas, then detects later edits and reloads', (tester) async {
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
    await _waitForMarkerAction(tester);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' edited');
    await tester.pump();

    await _tapVisible(tester, _marker);
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
    expect(store.library.current.githubBaseline?.path, 'Maths.canvas.json');
    expect(store.library.file('other').githubBaseline, isNull);
    expect(find.text('View commit'), findsOneWidget);
    expect(_marker, findsNothing);

    await tester.pumpWidget(const SizedBox());
    store.library = CanvasLibrary.fromJson(store.library.toJson());
    await _pumpWorkspace(tester, store, api, navigate: (_) {}, consumeCompletion: () => true);
    await _waitForEnabledButton(tester, _importButton);
    await _closeSync(tester);
    expect(_marker, findsNothing);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' later');
    await tester.pump();
    expect(_marker, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    expect(_marker, findsOneWidget);
    expect(store.library.current.document?.elements.whereType<TextElementData>().single.markdown, 'Maths edited later');
  });

  testWidgets('a commit preserves edits made after its capture', (tester) async {
    final store = _savedStore();
    final refUpdate = Completer<http.Response>();
    var patches = 0;
    final api = _commitApi(
      github: (request) async {
        if (request.method == 'PATCH') {
          patches++;
          return await refUpdate.future;
        }
        return _commitResponse(request);
      },
    );
    final captured = store.library.current.document!;
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await _waitForMarkerAction(tester);
    await _tapVisible(tester, _marker);
    await pumpUntil(tester, () => find.text('Commit').evaluate().isNotEmpty);
    await _tapVisible(tester, find.text('Cancel'));
    await _waitForMarkerAction(tester);
    expect(patches, 0);
    expect(store.library.current.githubBaseline, isNull);

    await _tapVisible(tester, _marker);
    await pumpUntil(tester, () => find.text('Commit').evaluate().isNotEmpty);
    await _tapVisible(tester, find.text('Commit'));
    await _pumpUntilBusySafe(tester, () => patches == 1, 'branch update');
    final canvas = tester.widget<TextElementView>(find.byType(TextElementView));
    canvas.resources.insertPastedText(' later');
    await tester.pump();
    refUpdate.complete(_json({'ref': 'refs/heads/main'}));
    await pumpUntil(tester, () => find.text('View commit').evaluate().isNotEmpty);
    expect(store.library.current.githubBaseline?.documentHash, GitHubBaseline.hashDocument(captured));
    expect(store.library.current.document, isNot(captured));
    expect(_marker, findsOneWidget);
  });

  testWidgets('a baseline save failure reports the confirmed commit without a second remote write', (tester) async {
    final store = _FailingLibraryStore(_document('saved'))..library = _savedStore().library;
    var patches = 0;
    final api = _commitApi(
      github: (request) async {
        if (request.method == 'PATCH') {
          patches++;
          store.failSaves = true;
          return _json({'ref': 'refs/heads/main'});
        }
        return _commitResponse(request);
      },
    );
    String? opened;
    await _pumpWorkspace(tester, store, api, navigate: (_) {}, open: (url) => opened = url);
    await _waitForMarkerAction(tester);
    await _tapVisible(tester, _marker);
    await pumpUntil(tester, () => find.text('Commit').evaluate().isNotEmpty);
    await _tapVisible(tester, find.text('Commit'));
    await pumpUntil(tester, () => find.text('View commit').evaluate().isNotEmpty);
    expect(find.textContaining('Canvas committed to GitHub. Could not save its local sync baseline.'), findsOneWidget);
    expect(store.library.current.githubBaseline, isNull);
    expect(_marker, findsOneWidget);
    await _tapVisible(tester, find.text('View commit'));
    expect(opened, 'https://github.com/owner/repo/commit/$_nextCommit');
    expect(patches, 1);
    store.failSaves = false;
  });

  testWidgets('detects attachment changes without changing the document or exporting the baseline', (tester) async {
    const image = 'attachments/4ff3ef0e-c35c-48fc-8d38-78569cc5b140.png';
    final document = _document('saved').copyWith(
      elements: [
        MediaElementData(id: 'image', position: Offset.zero, width: 160, url: image),
      ],
    );
    final baseline = GitHubBaseline.capture(_destination, 'Physics.canvas.json', document, {image: onePixelPngBytes});
    final store = _savedStore();
    store.library = store.library.replace(store.library.current.copyWith(document: document, githubBaseline: baseline));
    final changedBytes = Uint8List.fromList([...onePixelPngBytes, 0]);
    final attachments = TestAttachmentStore({image: changedBytes});
    final api = _commitApi(github: (_) async => _json({'error': 'not found'}, status: 404));
    await _pumpWorkspace(tester, store, api, navigate: (_) {}, attachments: attachments);
    await _waitForMarkerAction(tester);
    expect(_marker, findsOneWidget);
    expect(store.library.current.document, same(document));

    final exported = await encodeTransfer(store.library, attachments, TransferScope.currentCanvas);
    final portable = jsonDecode(utf8.decode(exported.files['Physics.canvas.json']!));
    expect(portable, document.toJson());
    expect(exported.files[image], changedBytes);
  });

  testWidgets('a late attachment match cannot clear the marker on another canvas', (tester) async {
    const image = 'attachments/4ff3ef0e-c35c-48fc-8d38-78569cc5b140.png';
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [MediaElementData(id: 'image', position: Offset.zero, width: 160, url: image)],
    );
    final baseline = GitHubBaseline.capture(_destination, 'Physics.canvas.json', document, {image: onePixelPngBytes});
    final store = _savedStore();
    store.library = CanvasLibrary(
      files: [
        store.library.current.copyWith(document: document, githubBaseline: baseline),
        CanvasFile(id: 'other', name: 'Chemistry', document: _document('other')),
      ],
      currentId: store.library.currentId,
      githubDestination: _destination,
    );
    final attachments = _DelayedAttachmentStore(image);
    final api = _commitApi(github: (_) async => _json({'error': 'not found'}, status: 404));
    await _pumpWorkspace(tester, store, api, navigate: (_) {}, attachments: attachments);
    await pumpUntil(tester, () => attachments.checkStarted);

    await _tapVisible(tester, find.text('Physics'));
    final other = find.byKey(const ValueKey('file-tree-node-other'));
    await pumpUntil(tester, () => other.evaluate().isNotEmpty);
    await _tapVisible(tester, other);
    await _waitForMarkerAction(tester);
    expect(store.library.currentId, 'other');
    attachments.complete();
    await tester.pumpAndSettle();
    expect(find.text('Chemistry'), findsOneWidget);
    expect(_marker, findsOneWidget);
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
        if (request.method == 'PATCH') {
          patches++;
          return _json({'message': 'unknown'}, status: 500);
        }
        return _commitResponse(request);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await _waitForMarkerAction(tester);

    for (var attempt = 1; attempt <= 2; attempt++) {
      await _tapVisible(tester, _marker);
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
      expect(find.text('Check GitHub'), findsOneWidget);
      expect(_marker, findsOneWidget);
      expect(store.library.current.githubBaseline, isNull);
      ScaffoldMessenger.of(tester.element(find.byType(SnackBar))).removeCurrentSnackBar();
      await _waitForMarkerAction(tester);
    }

    expect(patches, 2);
  });
}

final Finder _repositoryPicker = find.byKey(const ValueKey('github-repository-select'));
final Finder _importButton = find.byKey(const ValueKey('github-import'));
final Finder _marker = find.byKey(const ValueKey('canvas-title-indicator'));
final Finder _commitAction = find.byKey(const ValueKey('canvas-title-action'));

Future<void> _openSync(WidgetTester tester) async {
  await _tapVisible(tester, find.byKey(const ValueKey('settings-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await _tapVisible(tester, find.text('Sync'));
  await tester.pump();
}

Future<void> _closeSync(WidgetTester tester) async {
  await _tapVisible(tester, find.byKey(const ValueKey('settings-close')));
  await tester.pumpAndSettle();
}

Future<void> _waitForRepositoryPicker(WidgetTester tester) => pumpUntil(
  tester,
  () =>
      _repositoryPicker.evaluate().isNotEmpty &&
      tester.widget<SearchableSelect<int?>>(_repositoryPicker).onChanged != null,
);

Future<void> _selectRepository(WidgetTester tester, String name) async {
  await _waitForRepositoryPicker(tester);
  await _tapVisible(tester, find.byKey(const ValueKey('searchable-select-trigger')));
  final search = find.byKey(const ValueKey('searchable-select-search'));
  await pumpUntil(tester, () => search.evaluate().isNotEmpty);
  await tester.enterText(search, name);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

Future<void> _waitForMarkerAction(WidgetTester tester) => pumpUntil(
  tester,
  () => _marker.evaluate().isNotEmpty && tester.widget<InkWell>(_marker).onTap != null,
);

TestLibraryStore _savedStore() {
  final document = _document('saved');
  return TestLibraryStore(document)
    ..library = CanvasLibrary(
      files: [CanvasFile(id: 'local', name: 'Physics', document: document)],
      currentId: 'local',
      githubDestination: _destination,
    );
}

http.Response _ref() => _json({
  'object': {'type': 'commit', 'sha': _head},
});

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
  ThemeData? theme,
  TestAttachmentStore? attachments,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? starlessLightThemeData,
      home: Workspace(
        libraryStore: store,
        attachmentStore: attachments ?? TestAttachmentStore(),
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
  http.Response Function()? logout,
}) {
  var failuresRemaining = failDiscoveryCount;
  return GitHubApi(
    mediatorUrl: Uri.parse('https://mediator.example'),
    mediatorClient: MockClient((request) async {
      if (request.url.path == '/oauth/github/token') return _json({'access_token': 'test-token'});
      if (request.url.path == '/session/logout' && logout != null) return logout();
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

GitHubApi _importApi(String path, CanvasDocument document, {List<String>? requests}) {
  final bytes = utf8.encode(jsonEncode(document.toJson()));
  return _commitApi(
    requests: requests,
    github: (request) async {
      final pathRequested = request.url.path;
      if (pathRequested.endsWith('/git/ref/heads/main')) return _ref();
      if (pathRequested.endsWith('/git/commits/$_head')) {
        return _json({
          'tree': {'sha': _tree},
        });
      }
      if (pathRequested.endsWith('/git/trees/$_tree')) {
        return _json({
          'truncated': false,
          'tree': [_treeEntry(path, _documentBlob, bytes.length), _treeEntry('README.md', _nextCommit, 7)],
        });
      }
      if (pathRequested.endsWith('/git/blobs/$_documentBlob')) {
        return _json({
          'sha': _documentBlob,
          'size': bytes.length,
          'encoding': 'base64',
          'content': base64Encode(bytes),
        });
      }
      return _json({'error': 'not found'}, status: 404);
    },
  );
}

http.Response _commitResponse(http.Request request) {
  final path = request.url.path;
  if (path.endsWith('/git/ref/heads/main')) return _ref();
  if (path.endsWith('/git/commits/$_head')) {
    return _json({
      'tree': {'sha': _tree},
    });
  }
  if (path.endsWith('/git/trees/$_tree')) return _json({'truncated': false, 'tree': <Object?>[]});
  if (request.method == 'POST' && path.endsWith('/git/blobs')) return _json({'sha': _documentBlob});
  if (request.method == 'POST' && path.endsWith('/git/trees')) return _json({'sha': _nextTree});
  if (request.method == 'POST' && path.endsWith('/git/commits')) return _json({'sha': _nextCommit});
  return _json({'error': 'not found'}, status: 404);
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

Map<String, Object?> _installation({String permission = 'write'}) => {
  'id': 23,
  'account': {'id': 7, 'login': 'owner'},
  'html_url': 'https://github.com/settings/installations/23',
  'permissions': {'contents': permission},
};

Map<String, Object?> _repositoryJson({
  int id = 13,
  String name = 'repo',
  bool canPull = true,
  bool canPush = true,
  String defaultBranch = 'main',
}) => {
  'id': id,
  'owner': {'login': 'owner'},
  'name': name,
  'full_name': 'owner/$name',
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

class _DelayedAttachmentStore extends TestAttachmentStore {
  _DelayedAttachmentStore(String image) : super({image: onePixelPngBytes});

  final _result = Completer<Uint8List?>();
  bool checkStarted = false;

  void complete() => _result.complete(onePixelPngBytes);

  @override
  Future<Uint8List?> readIfExists(String path) {
    checkStarted = true;
    return _result.future;
  }
}
