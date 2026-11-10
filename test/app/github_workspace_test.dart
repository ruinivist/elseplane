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
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../canvas/test_helpers.dart';

void main() {
  testWidgets('hides GitHub actions when no API is configured', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document('saved')));

    expect(find.byKey(const ValueKey('github-connect')), findsNothing);
  });

  testWidgets('restores the GitHub account after consuming the completion marker', (tester) async {
    var completionChecks = 0;
    final api = _commitApi(
      github: (request) async => request.url.path == '/user'
          ? _json({'id': 17, 'login': 'canvas-user'})
          : _json({'error': 'not found'}, status: 404),
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
    await pumpUntil(tester, () => find.text('@canvas-user').evaluate().isNotEmpty);

    expect(completionChecks, 1);
    expect(find.byKey(const ValueKey('github-connect')), findsNothing);
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
        if (request.url.path == '/user') return _json({'id': 7, 'login': 'owner'});
        if (request.url.path == '/repos/owner/repo') return _json({'id': 13});
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({'message': 'private response'}, status: 401);
        }
        return _json({'message': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await pumpUntil(tester, () => find.byKey(const ValueKey('github-open')).hitTestable().evaluate().isNotEmpty);

    await tester.ensureVisible(find.byKey(const ValueKey('github-open')));
    await tester.tap(find.byKey(const ValueKey('github-open')));
    await pumpUntil(tester, () => find.byKey(const ValueKey('github-connect')).evaluate().isNotEmpty);

    expect(requests, contains('GET /repos/owner/repo'));
    expect(requests, contains('GET /repos/owner/repo/git/ref/heads/main'));
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('github-connect'))).onPressed, isNotNull);
    expect(find.text('Reconnect GitHub to continue.').evaluate(), isNotEmpty);
    expect(find.textContaining('private response'), findsNothing);
    expect(store.library.githubDestination?.toJson(), _destination.toJson());
    expect(store.library.current.document?.elements.whereType<TextElementData>().single.markdown, 'saved');
  });

  testWidgets('nested remote import clears its related pending write after saving', (tester) async {
    final localDocument = _document('Local Physics');
    final tracking = GitHubCanvasTracking(
      path: 'University/Physics.canvas',
      documentSha: _documentBlob,
      attachmentShas: const {},
      attachmentNames: const {},
    );
    final store = TestLibraryStore(localDocument)
      ..library = CanvasLibrary(
        files: [
          CanvasFile(
            id: 'physics',
            name: 'Physics',
            document: localDocument,
            githubTracking: GitHubCanvasTracking(
              path: 'Old/Physics.canvas',
              documentSha: _baseCommit,
              attachmentShas: const {},
              attachmentNames: const {},
            ),
            githubPendingTracking: tracking,
          ),
        ],
        currentId: 'physics',
        githubDestination: _destination,
      );
    final remoteDocument = _document('Remote Physics');
    final remoteBytes = utf8.encode(jsonEncode(remoteDocument.toJson()));
    final requests = <String>[];
    final api = _commitApi(
      github: (request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/user') return _json({'id': 7, 'login': 'owner'});
        if (request.url.path == '/repos/owner/repo') return _json({'id': 13});
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({
            'object': {'type': 'commit', 'sha': _baseCommit},
          });
        }
        if (request.url.path.endsWith('/git/commits/$_baseCommit')) {
          return _json({
            'tree': {'sha': _baseTree},
          });
        }
        if (request.url.path.endsWith('/git/trees/$_baseTree')) {
          return _json({
            'truncated': false,
            'tree': [
              {
                'path': 'University/Physics.canvas',
                'sha': _documentBlob,
                'type': 'blob',
                'mode': '100644',
                'size': remoteBytes.length,
              },
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
        return _json({'message': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('github-check-remote')).evaluate().isNotEmpty,
    );
    expect(find.textContaining('Check remote status before retrying'), findsOneWidget);
    expect(find.text('Check remote status'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'initial write-guard panel');

    expect(store.library.file('physics').githubWriteUnconfirmed, isTrue);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-commit'))).onPressed, isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('github-open')));
    await tester.tap(find.byKey(const ValueKey('github-open')));
    await _pumpUntilBusySafe(
      tester,
      () =>
          find.byKey(const ValueKey('github-canvas-University/Physics.canvas')).hitTestable().evaluate().isNotEmpty ||
          find.byType(SnackBar).evaluate().isNotEmpty,
      'remote canvas choice',
    );
    if (find.byKey(const ValueKey('github-canvas-University/Physics.canvas')).evaluate().isEmpty) {
      final message = (tester.widget<SnackBar>(find.byType(SnackBar)).content as Text).data;
      fail('Could not load the remote canvas list: $message; requests: ${requests.join(', ')}');
    }
    expect(tester.takeException(), isNull, reason: 'loading remote canvas choices');
    await tester.tap(find.byKey(const ValueKey('github-canvas-University/Physics.canvas')));
    await pumpUntil(
      tester,
      () => store.library.files.any((file) => file.parentId != null && file.name == 'Physics'),
    );
    expect(tester.takeException(), isNull, reason: 'importing nested remote canvas');

    expect(find.byKey(const ValueKey('github-canvas-name')), findsNothing);
    final rootCanvas = store.library.file('physics');
    expect(rootCanvas.document?.elements.whereType<TextElementData>().single.markdown, 'Local Physics');
    expect(rootCanvas.githubWriteUnconfirmed, isFalse);
    expect(rootCanvas.githubTracking?.path, 'Old/Physics.canvas');
    expect(rootCanvas.githubPendingTracking, isNull);
    final folder = store.library.files.singleWhere((file) => file.name == 'University' && file.isFolder);
    final imported = store.library.files.singleWhere((file) => file.parentId == folder.id && file.name == 'Physics');
    expect(imported.document?.elements.whereType<TextElementData>().single.markdown, 'Remote Physics');
    expect(store.library.current.id, imported.id);
    expect(imported.githubTracking?.path, 'University/Physics.canvas');
    expect(store.persisted?.elements.whereType<TextElementData>().single.markdown, 'Remote Physics');
  });

  testWidgets('confirming a destination for a different account clears tracking only', (tester) async {
    final document = _document('preserved');
    final store = TestLibraryStore(document)
      ..library = CanvasLibrary(
        files: [
          CanvasFile(
            id: 'local',
            name: 'Physics',
            document: document,
            githubTracking: GitHubCanvasTracking(
              path: 'Physics.canvas',
              documentSha: _documentBlob,
              attachmentShas: const {},
              attachmentNames: const {},
            ),
            githubPendingTracking: GitHubCanvasTracking(
              path: 'Physics-pending.canvas',
              documentSha: _nextCommit,
              attachmentShas: const {},
              attachmentNames: const {},
            ),
          ),
        ],
        currentId: 'local',
        githubDestination: _destination,
      );
    final api = _commitApi(
      github: (request) async {
        if (request.url.path == '/user') return _json({'id': 17, 'login': 'new-owner'});
        if (request.url.path == '/repos/owner/repo') {
          return _json({
            'id': 13,
            'owner': {'login': 'owner'},
            'name': 'repo',
            'default_branch': 'main',
            'private': false,
          });
        }
        return _json({'message': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await pumpUntil(tester, () => find.byKey(const ValueKey('github-repository')).evaluate().isNotEmpty);
    expect(tester.takeException(), isNull, reason: 'restoring mismatched account');

    tester.widget<TextButton>(find.byKey(const ValueKey('github-repository'))).onPressed!.call();
    await _pumpUntilBusySafe(
      tester,
      () => find.byKey(const ValueKey('github-repository-field')).evaluate().isNotEmpty,
      'repository form',
    );
    expect(tester.takeException(), isNull, reason: 'opening repository form');
    await tester.tap(find.text('Continue'));
    await _pumpUntilBusySafe(
      tester,
      () => find.text('Use repository').evaluate().isNotEmpty,
      'destination confirmation',
    );
    expect(tester.takeException(), isNull, reason: 'fetching selected repository');
    expect(find.textContaining('clears saved GitHub links'), findsOneWidget);
    await tester.tap(find.text('Use repository'));
    await _pumpUntilBusySafe(tester, () => store.library.githubDestination?.accountId == 17, 'destination persistence');
    expect(tester.takeException(), isNull, reason: 'persisting account destination');

    expect(store.library.current.document, same(document));
    expect(store.library.current.githubTracking, isNull);
    expect(store.library.current.githubWriteUnconfirmed, isFalse);
  });

  testWidgets('repository form remains usable in a short viewport', (tester) async {
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
              onPressed: () => showGitHubRepositoryDialog(context, initial: ''),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('github-repository-field')).hitTestable(), findsOneWidget);
    expect(find.text('Enter owner/repository'), findsOneWidget);
    expect(find.text('Continue').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canvas name form remains usable in a short viewport', (tester) async {
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
              onPressed: () => showGitHubCanvasNameDialog(
                context,
                initial: '',
                message: 'Choose a different name for this remote canvas.',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('github-canvas-name')).hitTestable(), findsOneWidget);
    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Import').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace interlock rejects duplicate GitHub operations', (tester) async {
    final response = Completer<http.Response>();
    final requests = <String>[];
    Uri? navigation;
    final api = _api(
      mediator: (request) {
        requests.add(request.url.path);
        return response.future;
      },
    );
    await _pumpWorkspace(
      tester,
      TestLibraryStore(_document('saved')),
      api,
      navigate: (uri) => navigation = uri,
    );

    final connect = tester.widget<TextButton>(find.byKey(const ValueKey('github-connect'))).onPressed!;
    await tester.tap(find.byKey(const ValueKey('github-connect')));
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
        mediatorRequests++;
        return _json({'authorization_url': 'https://github.com/login/oauth/authorize?client_id=app'});
      },
    );
    await _pumpWorkspace(
      tester,
      store,
      api,
      navigate: (_) => navigations++,
    );
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' unsaved');
    await tester.pump();
    store.failSaves = true;

    await tester.tap(find.byKey(const ValueKey('github-connect')));
    await pumpUntil(
      tester,
      () => find.text('Could not save canvas. GitHub authorization was not started.').evaluate().isNotEmpty,
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
        mediatorRequests++;
        return _json({'authorization_url': 'https://github.com/login/oauth/authorize?client_id=app'});
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (uri) => navigation = uri);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' after');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('github-connect')));
    await pumpUntil(tester, () => navigation != null);

    expect(store.persisted, isNotNull);
    expect(store.persisted!.elements.whereType<TextElementData>().single.markdown, 'before after');
    expect(mediatorRequests, 1);
    expect(navigation?.host, 'github.com');
  });

  testWidgets('keeps an uncertain guard when remote commit succeeds but tracking save fails', (tester) async {
    final store = _RecordingLibraryStore(_document('Maths'));
    final current = store.library.current.copyWith(name: 'Maths');
    store.library = CanvasLibrary(
      currentId: current.id,
      githubDestination: _destination,
      files: [
        current,
        CanvasFile(id: 'physics', name: 'Physics', document: _document('Uncommitted Physics')),
      ],
    );
    final openUrls = <String>[];
    final requestBodies = <Map<String, Object?>>[];
    final requests = <String>[];
    var referenceUpdates = 0;
    final api = _commitApi(
      github: (request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/user') return _json({'id': 7, 'login': 'owner'});
        if (request.method == 'GET' && request.url.path == '/repos/owner/repo') return _json({'id': 13});
        if (request.method == 'GET' && request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({
            'object': {'type': 'commit', 'sha': _baseCommit},
          });
        }
        if (request.url.path.endsWith('/git/commits/$_baseCommit')) {
          return _json({
            'tree': {'sha': _baseTree},
          });
        }
        if (request.url.path.endsWith('/git/trees/$_baseTree')) {
          return _json({'truncated': false, 'tree': <Object?>[]});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) {
          requestBodies.add(jsonDecode(request.body) as Map<String, Object?>);
          return _json({'sha': _documentBlob});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) {
          return _json({'sha': _nextTree});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) {
          return _json({'sha': _nextCommit, 'html_url': 'https://github.com/owner/repo/commit/$_nextCommit'});
        }
        if (request.method == 'PATCH' && request.url.path.endsWith('/git/refs/heads/main')) {
          referenceUpdates++;
          return _json({'ref': 'refs/heads/main'});
        }
        return _json({'message': 'not found'}, status: 404);
      },
    );
    store.failTrackingConfirmation = true;
    await _pumpWorkspace(tester, store, api, navigate: (_) {}, open: openUrls.add);
    await pumpUntil(tester, () => find.byKey(const ValueKey('github-commit')).hitTestable().evaluate().isNotEmpty);
    tester.widget<TextElementView>(find.byType(TextElementView)).resources.insertPastedText(' edited');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('github-commit')));
    await _pumpUntilBusySafe(
      tester,
      () =>
          find.byKey(const ValueKey('github-commit-message')).evaluate().isNotEmpty ||
          find.byType(SnackBar).evaluate().isNotEmpty,
      'commit confirmation',
    );
    if (find.byKey(const ValueKey('github-commit-message')).evaluate().isEmpty) {
      final message = (tester.widget<SnackBar>(find.byType(SnackBar)).content as Text).data;
      fail('Commit confirmation failed: $message; requests: ${requests.join(', ')}');
    }
    await tester.tap(find.text('Commit'));
    await _pumpUntilBusySafe(
      tester,
      () =>
          find.textContaining('GitHub accepted the commit').evaluate().isNotEmpty ||
          find.byType(SnackBar).evaluate().isNotEmpty,
      'commit result',
    );
    if (find.textContaining('GitHub accepted the commit').evaluate().isEmpty) {
      final message = (tester.widget<SnackBar>(find.byType(SnackBar)).content as Text).data;
      fail('GitHub action failed: $message; requests: ${requests.join(', ')}');
    }

    expect(referenceUpdates, 1);
    expect(requestBodies, hasLength(1));
    final sentDocument =
        jsonDecode(utf8.decode(base64Decode(requestBodies.single['content']! as String))) as Map<String, Object?>;
    final sentElements = sentDocument['elements']! as List<Object?>;
    expect((sentElements.single! as Map<String, Object?>)['markdown'], 'Maths edited');
    expect(jsonEncode(sentDocument), isNot(contains('Uncommitted Physics')));
    expect(store.savedSnapshots.last.file(current.id).githubWriteUnconfirmed, isTrue);
    expect(store.savedSnapshots.last.file(current.id).githubTracking, isNull);
    expect(store.savedSnapshots.last.file(current.id).githubPendingTracking?.path, 'Maths.canvas');
    expect(store.savedSnapshots.last.file('physics').githubTracking, isNull);

    await tester.tap(find.text('Open on GitHub'));
    await tester.pumpAndSettle();
    expect(openUrls.single, 'https://github.com/owner/repo/commit/$_nextCommit');
  });

  testWidgets('checking an absent initial publication unlocks a manual retry', (tester) async {
    final store = TestLibraryStore(_document('Maths'));
    final file = store.library.current.copyWith(name: 'Maths');
    store.library = CanvasLibrary(
      currentId: file.id,
      githubDestination: _destination,
      files: [
        file.copyWith(
          githubPendingTracking: GitHubCanvasTracking(
            path: 'Maths.canvas',
            documentSha: _nextCommit,
            attachmentShas: const {},
            attachmentNames: const {},
          ),
        ),
      ],
    );
    var patches = 0;
    final api = _commitApi(
      github: (request) async {
        if (request.url.path == '/user') return _json({'id': 7, 'login': 'owner'});
        if (request.method == 'GET' && request.url.path == '/repos/owner/repo') return _json({'id': 13});
        if (request.url.path.endsWith('/git/ref/heads/main')) {
          return _json({
            'object': {'type': 'commit', 'sha': _baseCommit},
          });
        }
        if (request.url.path.endsWith('/git/commits/$_baseCommit')) {
          return _json({
            'tree': {'sha': _baseTree},
          });
        }
        if (request.url.path.endsWith('/git/trees/$_baseTree')) {
          return _json({'truncated': false, 'tree': <Object?>[]});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) return _json({'sha': _documentBlob});
        if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) return _json({'sha': _nextTree});
        if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) {
          return _json({'sha': _nextCommit});
        }
        if (request.method == 'PATCH') {
          patches++;
          return _json({'ref': 'refs/heads/main'});
        }
        return _json({'message': 'not found'}, status: 404);
      },
    );
    await _pumpWorkspace(tester, store, api, navigate: (_) {});
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('github-check-remote')).evaluate().isNotEmpty,
    );

    expect(store.library.current.githubWriteUnconfirmed, isTrue);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-commit'))).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('github-check-remote')));
    await tester.tap(find.byKey(const ValueKey('github-check-remote')));
    await _pumpUntilBusySafe(tester, () => store.library.current.githubPendingTracking == null, 'initial status check');
    expect(store.library.current.githubTracking, isNull);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('github-commit'))).onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const ValueKey('github-commit')));
    await tester.tap(find.byKey(const ValueKey('github-commit')));
    await _pumpUntilBusySafe(
      tester,
      () => find.byKey(const ValueKey('github-commit-message')).evaluate().isNotEmpty,
      'commit dialog after status check',
    );
    await tester.tap(find.text('Commit'));
    await _pumpUntilBusySafe(
      tester,
      () => patches == 1 && store.library.current.githubTracking != null,
      'manual retry result',
    );
    expect(store.library.current.githubTracking?.path, 'Maths.canvas');
    expect(store.library.current.githubPendingTracking, isNull);
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
        navigateGitHubAuthorization: navigate,
        consumeGitHubCompletion: consumeCompletion ?? () => false,
        openGitHubLink: open ?? (_) {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

GitHubApi _api({required Future<http.Response> Function(http.Request) mediator}) => GitHubApi(
  mediatorUrl: Uri.parse('https://mediator.example'),
  mediatorClient: MockClient(mediator),
  githubClient: MockClient((_) async => _json({'id': 1, 'login': 'owner'})),
);

GitHubApi _commitApi({required Future<http.Response> Function(http.Request) github}) => GitHubApi(
  mediatorUrl: Uri.parse('https://mediator.example'),
  mediatorClient: MockClient((request) async {
    if (request.url.path == '/oauth/github/token') return _json({'access_token': 'test-token', 'scope': 'repo'});
    return _json({'error': 'not found'}, status: 404);
  }),
  githubClient: MockClient(github),
);

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

class _RecordingLibraryStore extends TestLibraryStore {
  _RecordingLibraryStore(super.initial);

  final savedSnapshots = <CanvasLibrary>[];
  bool failTrackingConfirmation = false;

  @override
  Future<void> save(CanvasLibrary snapshot) async {
    final current = snapshot.current;
    if (failTrackingConfirmation && current.githubTracking != null && current.githubPendingTracking == null) {
      throw StateError('storage unavailable');
    }
    savedSnapshots.add(snapshot);
    await super.save(snapshot);
  }
}

const _destination = GitHubDestination(
  accountId: 7,
  repositoryId: 13,
  owner: 'owner',
  repository: 'repo',
  branch: 'main',
);
const _baseCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _baseTree = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _documentBlob = 'cccccccccccccccccccccccccccccccccccccccc';
const _nextTree = 'dddddddddddddddddddddddddddddddddddddddd';
const _nextCommit = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
