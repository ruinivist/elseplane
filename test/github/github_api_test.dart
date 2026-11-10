import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:elseplane/library/transfer/canvas_remote_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _mediator = 'https://mediator.example';
const _commitSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _treeSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _documentSha = 'cccccccccccccccccccccccccccccccccccccccc';
const _blobSha = 'dddddddddddddddddddddddddddddddddddddddd';
const _imageSha = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _imagePath = 'attachments/123e4567-e89b-42d3-a456-426614174000.png';
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8DwHwAFAAH/VscvDQAAAABJRU5ErkJggg==';

GitHubDestination _destination({String branch = 'main'}) => GitHubDestination(
  accountId: 1,
  repositoryId: 2,
  owner: 'owner',
  repository: 'repo',
  branch: branch,
);

CanvasProject _emptyProject() => CanvasProject(
  document: CanvasDocument(background: CanvasBackgroundKind.dotGrid, elements: const []),
  attachments: const {},
);

Uint8List _emptyDocumentBytes() => encodeRemoteCanvasDocument(_emptyProject().document);

http.Response _json(Object? value, {int status = 200, Map<String, String> headers = const {}}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

http.Response _blob(String sha, List<int> bytes) => _json({
  'sha': sha,
  'size': bytes.length,
  'encoding': 'base64',
  'content': base64.encode(bytes),
});

http.Response _wrappedBlob(String sha, List<int> bytes) {
  final encoded = base64.encode(bytes);
  final content = StringBuffer();
  for (var start = 0; start < encoded.length; start += 60) {
    if (start > 0) content.write('\n');
    content.write(encoded.substring(start, start + 60 < encoded.length ? start + 60 : encoded.length));
  }
  return _json({'sha': sha, 'size': bytes.length, 'encoding': 'base64', 'content': content.toString()});
}

http.Response _user({Map<String, String> headers = const {}}) => _json(
  {'id': 1, 'login': 'owner'},
  headers: {'x-oauth-scopes': 'repo, user:email', ...headers},
);

http.Response _repositoryIdentity({int id = 2}) => _json({'id': id});

http.Response _ref() => _json({
  'object': {'type': 'commit', 'sha': _commitSha},
});

http.Response _commit() => _json({
  'tree': {'sha': _treeSha},
});

List<Map<String, Object?>> _treeEntries(
  List<({String path, String sha, String type, String mode, int? size})> entries,
) => [
  for (final entry in entries)
    {
      'path': entry.path,
      'sha': entry.sha,
      'type': entry.type,
      'mode': entry.mode,
      if (entry.size != null) 'size': entry.size,
    },
];

GitHubApi _api({
  required Future<http.Response> Function(http.Request request) github,
  Future<http.Response> Function(http.Request request)? mediator,
}) => GitHubApi(
  mediatorUrl: Uri.parse(_mediator),
  mediatorClient: MockClient(mediator ?? _defaultMediator),
  githubClient: MockClient(github),
);

Future<http.Response> _defaultMediator(http.Request request) async {
  if (request.method != 'POST' || request.body != '{}') return _json({'error': 'not found'}, status: 404);
  if (request.url.path == '/oauth/github/start') {
    return _json({'authorization_url': 'https://github.com/login/oauth/authorize?client_id=app'});
  }
  if (request.url.path == '/session/logout') return http.Response('', 204);
  if (request.url.path == '/oauth/github/token') {
    return _json({'access_token': 'secret-token', 'token_type': 'Bearer', 'scope': 'repo'});
  }
  return _json({'error': 'not found'}, status: 404);
}

Future<http.Response> _snapshotRoute(
  http.Request request, {
  required List<Map<String, Object?>> tree,
  Map<String, ({String sha, List<int> bytes})> blobs = const {},
}) async {
  if (request.url.path == '/user') return _user();
  if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
  if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
  if (request.url.path.endsWith('/git/commits/$_commitSha')) return _commit();
  if (request.url.path.endsWith('/git/trees/$_treeSha')) return _json({'truncated': false, 'tree': tree});
  for (final entry in blobs.entries) {
    if (request.url.path.endsWith('/git/blobs/${entry.key}')) return _blob(entry.value.sha, entry.value.bytes);
  }
  return _json({'message': 'not found'}, status: 404);
}

Map<String, Object?> _treeEntry(String path, String sha) => {
  'path': path,
  'sha': sha,
  'type': 'blob',
  'mode': '100644',
};

GitHubApi _pendingCheckApi(List<Map<String, Object?>> tree, {void Function(http.Request request)? onRequest}) => _api(
  github: (request) async {
    onRequest?.call(request);
    if (request.url.path == '/user') return _user();
    if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
    return await _snapshotRoute(request, tree: tree);
  },
);

void main() {
  group('OAuth and account', () {
    test('uses mediator POST contract, validates GitHub user and accepts optional expiry', () async {
      final mediatorRequests = <http.Request>[];
      final githubRequests = <http.Request>[];
      final api = _api(
        mediator: (request) async {
          mediatorRequests.add(request);
          return await _defaultMediator(request);
        },
        github: (request) async {
          githubRequests.add(request);
          return _user();
        },
      );

      final authorization = await api.startAuthorization();
      final account = await api.account();

      expect(authorization.host, 'github.com');
      expect(account.id, 1);
      expect(account.login, 'owner');
      expect(mediatorRequests, hasLength(2));
      for (final request in mediatorRequests) {
        expect(request.method, 'POST');
        expect(request.body, '{}');
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.headers['X-OAuth-Bridge'], '1');
        expect(request.url.host, 'mediator.example');
      }
      expect(githubRequests.single.headers['Authorization'], 'Bearer secret-token');
      expect(githubRequests.single.headers.containsKey('Cookie'), isFalse);
    });

    test('rejects unsafe authorization urls and missing repo scope', () async {
      final unsafe = _api(
        mediator: (request) async => _json({'authorization_url': 'https://github.com.evil.test/login/oauth/authorize'}),
        github: (_) async => _user(),
      );
      await expectLater(unsafe.startAuthorization(), throwsA(isA<GitHubApiException>()));

      final noScope = _api(
        mediator: (request) async => _json({'access_token': 'x', 'scope': 'read:user'}),
        github: (_) async => _user(headers: const {'x-oauth-scopes': 'repo'}),
      );
      await expectLater(
        noScope.account(),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.insufficientScope)),
      );
    });

    test('rejects explicit empty scopes but accepts omitted scope fields', () async {
      for (final scope in ['', '   ']) {
        final tokenScope = _api(
          mediator: (_) async => _json({'access_token': 'secret-token', 'scope': scope}),
          github: (_) async => _user(),
        );
        await expectLater(
          tokenScope.account(),
          throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.insufficientScope)),
          reason: 'Rejected token scope "$scope"',
        );

        final githubScope = _api(
          mediator: (_) async => _json({'access_token': 'secret-token', 'scope': 'repo'}),
          github: (_) async => _user(headers: {'x-oauth-scopes': scope}),
        );
        await expectLater(
          githubScope.account(),
          throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.insufficientScope)),
          reason: 'Rejected GitHub scope "$scope"',
        );
      }

      final omitted = _api(
        mediator: (_) async => _json({'access_token': 'secret-token'}),
        github: (_) async => _json({'id': 1, 'login': 'owner'}),
      );
      expect((await omitted.account()).id, 1);
    });

    test('repository lookup uses default branch and exposes visibility', () async {
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') {
            return _json({
              'id': 2,
              'name': 'repo',
              'owner': {'login': 'owner'},
              'default_branch': 'main',
              'private': true,
            });
          }
          return _json({'message': 'not found'}, status: 404);
        },
      );
      final destination = await api.repository('owner/repo');
      expect(destination.branch, 'main');
      expect(destination.repositoryId, 2);
      expect(api.lastRepositoryPrivate, isTrue);
      await expectLater(api.repository('owner/repo/tree/main'), throwsA(isA<GitHubApiException>()));
    });

    test('logout accepts empty 204 and non-JSON failures stay sanitized', () async {
      var logoutBody = '';
      final api = _api(
        mediator: (request) async {
          if (request.url.path == '/session/logout') {
            logoutBody = request.body;
            return http.Response('', 204);
          }
          return http.Response('<html>token=secret-token</html>', 502);
        },
        github: (_) async => _user(),
      );
      await api.logout();
      expect(logoutBody, '{}');
      await expectLater(
        api.account(),
        throwsA(isA<GitHubApiException>().having((e) => e.toString(), 'message', isNot(contains('secret-token')))),
      );
    });
  });

  group('GitHub failures', () {
    test('403 reset headers alone do not classify permission denials as rate limits', () async {
      final reset = ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 60).toString();
      var mediatorRequests = 0;
      var githubRequests = 0;
      final api = _api(
        mediator: (request) async {
          mediatorRequests++;
          return await _defaultMediator(request);
        },
        github: (_) async {
          githubRequests++;
          return _json(
            {'message': 'forbidden'},
            status: 403,
            headers: {'x-ratelimit-remaining': '10', 'x-ratelimit-reset': reset},
          );
        },
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          api.account(),
          throwsA(
            isA<GitHubApiException>()
                .having((error) => error.kind, 'kind', GitHubErrorKind.permissionDenied)
                .having((error) => error.retryAfter, 'retryAfter', isNull)
                .having((error) => error.toString(), 'message', contains('permissions')),
          ),
        );
      }
      expect(mediatorRequests, 2);
      expect(githubRequests, 2);
    });

    test('403 with exhausted rate limit uses reset timing', () async {
      final reset = ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 30).toString();
      final api = _api(
        github: (_) async => _json(
          {'message': 'rate limited'},
          status: 403,
          headers: {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': reset},
        ),
      );

      await expectLater(
        api.account(),
        throwsA(
          isA<GitHubApiException>()
              .having((error) => error.kind, 'kind', GitHubErrorKind.rateLimited)
              .having(
                (error) => error.retryAfter,
                'retryAfter',
                predicate<Duration?>(
                  (delay) => delay != null && delay > Duration.zero && delay <= const Duration(seconds: 30),
                ),
              )
              .having((error) => error.toString(), 'message', contains('Wait before trying again')),
        ),
      );
    });

    test('blocks all requests during the Retry-After window', () async {
      var mediatorRequests = 0;
      var githubRequests = 0;
      final api = _api(
        mediator: (request) async {
          mediatorRequests++;
          return await _defaultMediator(request);
        },
        github: (_) async {
          githubRequests++;
          return _json({'message': 'rate limited'}, status: 429, headers: {'retry-after': '60'});
        },
      );

      await expectLater(
        api.account(),
        throwsA(
          isA<GitHubApiException>()
              .having((error) => error.kind, 'kind', GitHubErrorKind.rateLimited)
              .having(
                (error) => error.retryAfter,
                'retryAfter',
                predicate<Duration?>(
                  (delay) => delay != null && delay > Duration.zero && delay <= const Duration(seconds: 60),
                ),
              ),
        ),
      );
      final requestsBeforeRetry = (mediatorRequests, githubRequests);
      await expectLater(
        api.account(),
        throwsA(
          isA<GitHubApiException>()
              .having((error) => error.kind, 'kind', GitHubErrorKind.rateLimited)
              .having((error) => error.retryAfter, 'retryAfter', greaterThan(Duration.zero)),
        ),
      );
      expect((mediatorRequests, githubRequests), requestsBeforeRetry);
    });

    test('uses a 60-second default when rate-limit timing is absent', () async {
      final api = _api(github: (_) async => _json({'message': 'rate limited'}, status: 429));

      await expectLater(
        api.account(),
        throwsA(
          isA<GitHubApiException>().having(
            (error) => error.retryAfter,
            'retryAfter',
            predicate<Duration?>(
              (delay) => delay != null && delay >= const Duration(seconds: 59) && delay <= const Duration(seconds: 60),
            ),
          ),
        ),
      );
    });

    test('allows a manual request after retry-after zero', () async {
      var mediatorRequests = 0;
      var githubRequests = 0;
      final api = _api(
        mediator: (request) async {
          mediatorRequests++;
          return await _defaultMediator(request);
        },
        github: (_) async {
          githubRequests++;
          return githubRequests == 1
              ? _json({'message': 'rate limited'}, status: 429, headers: {'retry-after': '0'})
              : _user();
        },
      );

      await expectLater(
        api.account(),
        throwsA(
          isA<GitHubApiException>()
              .having((error) => error.kind, 'kind', GitHubErrorKind.rateLimited)
              .having((error) => error.retryAfter, 'retryAfter', Duration.zero),
        ),
      );
      expect((await api.account()).id, 1);
      expect(mediatorRequests, 2);
      expect(githubRequests, 2);
    });
  });

  group('snapshot and import', () {
    test('verifies the saved repository identity before reading its tree', () async {
      final githubRequests = <http.Request>[];
      final api = _api(
        github: (request) async {
          githubRequests.add(request);
          return await _snapshotRoute(request, tree: const []);
        },
      );

      final snapshot = await api.snapshot(_destination());

      expect(snapshot.entries, isEmpty);
      expect(githubRequests.map((request) => request.url.path), [
        '/user',
        '/repos/owner/repo',
        '/repos/owner/repo/git/ref/heads/main',
        '/repos/owner/repo/git/commits/$_commitSha',
        '/repos/owner/repo/git/trees/$_treeSha',
      ]);
    });

    test('rejects a recreated repository before any object read or write', () async {
      final githubRequests = <http.Request>[];
      final api = _api(
        github: (request) async {
          githubRequests.add(request);
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity(id: 13);
          return _json({'message': 'unexpected request'}, status: 404);
        },
      );
      final destination = _destination();
      final snapshot = GitHubSnapshot(
        commitSha: _commitSha,
        treeSha: _treeSha,
        entries: {
          'Maths.canvas': const GitHubTreeEntry(
            path: 'Maths.canvas',
            sha: _documentSha,
            type: 'blob',
            mode: '100644',
            size: 0,
          ),
        },
      );
      final changedIdentity = throwsA(
        isA<GitHubApiException>()
            .having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)
            .having(
              (error) => error.message,
              'message',
              'Repository identity changed. Choose the repository again before transferring.',
            ),
      );

      await expectLater(api.snapshot(destination), changedIdentity);
      await expectLater(api.openCanvas(destination, snapshot, 'Maths.canvas'), changedIdentity);
      await expectLater(
        api.commitCanvas(
          destination: destination,
          path: 'Maths.canvas',
          project: _emptyProject(),
          message: 'docs: save canvas',
          beforeRefUpdate: (_, _) async {},
        ),
        changedIdentity,
      );

      expect(githubRequests.map((request) => request.url.path), [
        for (var attempt = 0; attempt < 3; attempt++) ...['/user', '/repos/owner/repo'],
      ]);
      expect(githubRequests.every((request) => request.method == 'GET'), isTrue);
    });

    test('canvas picker excludes symlinks, submodules, and trees', () {
      final snapshot = GitHubSnapshot(
        commitSha: _commitSha,
        treeSha: _treeSha,
        entries: {
          'valid.canvas': const GitHubTreeEntry(
            path: 'valid.canvas',
            sha: _documentSha,
            type: 'blob',
            mode: '100644',
          ),
          'link.canvas': const GitHubTreeEntry(
            path: 'link.canvas',
            sha: _blobSha,
            type: 'blob',
            mode: '120000',
          ),
          'submodule.canvas': const GitHubTreeEntry(
            path: 'submodule.canvas',
            sha: _imageSha,
            type: 'commit',
            mode: '160000',
          ),
          'directory.canvas': const GitHubTreeEntry(
            path: 'directory.canvas',
            sha: _treeSha,
            type: 'tree',
            mode: '040000',
          ),
        },
      );
      expect(snapshot.canvasPaths, ['valid.canvas']);
    });

    test('reserves only the literal attachments path segment', () async {
      final requests = <String>[];
      final api = _api(
        github: (request) async {
          requests.add(request.url.path);
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
          return _json({'message': 'not found'}, status: 404);
        },
      );
      final snapshot = GitHubSnapshot(commitSha: _commitSha, treeSha: _treeSha, entries: const {});

      await expectLater(
        api.openCanvas(_destination(), snapshot, 'attachments/Map.canvas'),
        throwsA(
          isA<GitHubApiException>().having((error) => error.message, 'message', contains('reserved attachments')),
        ),
      );
      await expectLater(
        api.openCanvas(_destination(), snapshot, 'Attachments/Map.canvas'),
        throwsA(
          isA<GitHubApiException>().having((error) => error.message, 'message', contains('not a regular GitHub file')),
        ),
      );

      expect(requests, ['/user', '/repos/owner/repo', '/user', '/repos/owner/repo']);
    });

    test('reads one recursive tree and rejects truncated results', () async {
      var recursiveReads = 0;
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            recursiveReads++;
            expect(request.url.queryParameters['recursive'], '1');
            return _json({'truncated': true, 'tree': <Map<String, Object?>>[]});
          }
          return await _snapshotRoute(request, tree: const []);
        },
      );
      await expectLater(
        api.snapshot(_destination()),
        throwsA(isA<GitHubApiException>().having((e) => e.toString(), 'message', contains('truncated'))),
      );
      expect(recursiveReads, 1);
    });

    test('imports by immutable blob sha and fetches only referenced sibling images', () async {
      final document = CanvasDocument(
        background: CanvasBackgroundKind.dotGrid,
        elements: [MediaElementData(id: 'media-1', position: Offset.zero, width: 120, url: _imagePath)],
      );
      final documentBytes = encodeRemoteCanvasDocument(document);
      const remoteImagePath = 'folder/$_imagePath';
      final imageBytes = base64.decode(_png);
      final fetchedShas = <String>[];
      final snapshot = GitHubSnapshot(
        commitSha: _commitSha,
        treeSha: _treeSha,
        entries: {
          'folder/Maths.canvas': GitHubTreeEntry(
            path: 'folder/Maths.canvas',
            sha: _documentSha,
            type: 'blob',
            mode: '100644',
            size: documentBytes.length,
          ),
          remoteImagePath: GitHubTreeEntry(
            path: remoteImagePath,
            sha: _imageSha,
            type: 'blob',
            mode: '100644',
            size: imageBytes.length,
          ),
          'folder/attachments/unused.png': const GitHubTreeEntry(
            path: 'folder/attachments/unused.png',
            sha: _blobSha,
            type: 'blob',
            mode: '100644',
            size: 10,
          ),
        },
      );
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
          if (request.url.path.endsWith('/git/blobs/$_documentSha')) {
            fetchedShas.add(_documentSha);
            return _blob(_documentSha, documentBytes);
          }
          if (request.url.path.endsWith('/git/blobs/$_imageSha')) {
            fetchedShas.add(_imageSha);
            return _blob(_imageSha, imageBytes);
          }
          return _json({'message': 'not found'}, status: 404);
        },
      );
      final project = await api.openCanvas(_destination(), snapshot, 'folder/Maths.canvas');
      expect(project.attachments.keys, [_imagePath]);
      expect(fetchedShas, [_documentSha, _imageSha]);
    });

    test('accepts a valid blob response near its bounded JSON limit', () async {
      final imageBytes = base64.decode(_png);
      final document = CanvasDocument(
        background: CanvasBackgroundKind.dotGrid,
        elements: [MediaElementData(id: 'media-1', position: Offset.zero, width: 120, url: _imagePath)],
      );
      final documentBytes = encodeRemoteCanvasDocument(document);
      final snapshot = GitHubSnapshot(
        commitSha: _commitSha,
        treeSha: _treeSha,
        entries: {
          'Canvas.canvas': GitHubTreeEntry(
            path: 'Canvas.canvas',
            sha: _documentSha,
            type: 'blob',
            mode: '100644',
            size: documentBytes.length,
          ),
          _imagePath: GitHubTreeEntry(
            path: _imagePath,
            sha: _imageSha,
            type: 'blob',
            mode: '100644',
            size: imageBytes.length,
          ),
        },
      );
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
          if (request.url.path.endsWith('/git/blobs/$_documentSha')) return _blob(_documentSha, documentBytes);
          if (request.url.path.endsWith('/git/blobs/$_imageSha')) {
            // Keep the base64 small while exercising the enlarged bounded-response allowance.
            final blob = _blob(_imageSha, imageBytes);
            return http.Response(blob.body.padRight(15_000_000), 200, headers: blob.headers);
          }
          return _json({'message': 'not found'}, status: 404);
        },
      );

      final project = await api.openCanvas(_destination(), snapshot, 'Canvas.canvas');

      expect(project.attachments[_imagePath], imageBytes);
    });

    test('opens a large canvas document with wrapped base64 content', () async {
      final sourceChunk = List<String>.filled(1024, 'x').join();
      final source = List<String>.filled(17 * 1024, sourceChunk).join();
      final document = CanvasDocument(
        background: CanvasBackgroundKind.dotGrid,
        elements: [
          CodeElementData(
            id: 'large-code',
            position: Offset.zero,
            size: const Size(600, 400),
            language: CodeLanguage.dart,
            source: source,
            title: 'large.dart',
            showLineNumbers: true,
          ),
        ],
      );
      final documentBytes = encodeRemoteCanvasDocument(document);
      expect(documentBytes.length, greaterThan(17 * 1024 * 1024));
      var responseBytes = 0;
      final snapshot = GitHubSnapshot(
        commitSha: _commitSha,
        treeSha: _treeSha,
        entries: {
          'Large.canvas': GitHubTreeEntry(
            path: 'Large.canvas',
            sha: _documentSha,
            type: 'blob',
            mode: '100644',
            size: documentBytes.length,
          ),
        },
      );
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
          if (request.url.path.endsWith('/git/blobs/$_documentSha')) {
            final response = _wrappedBlob(_documentSha, documentBytes);
            responseBytes = response.bodyBytes.length;
            return response;
          }
          return _json({'message': 'not found'}, status: 404);
        },
      );

      final project = await api.openCanvas(_destination(), snapshot, 'Large.canvas');

      expect(responseBytes, greaterThan(16 * 1024 * 1024));
      expect((project.document.elements.single as CodeElementData).source, source);
    });

    test('rejects malformed and noncanonical base64 blob content', () async {
      var content = '';
      final snapshot = GitHubSnapshot(
        commitSha: _commitSha,
        treeSha: _treeSha,
        entries: {
          'Invalid.canvas': const GitHubTreeEntry(
            path: 'Invalid.canvas',
            sha: _documentSha,
            type: 'blob',
            mode: '100644',
            size: 1,
          ),
        },
      );
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
          if (request.url.path.endsWith('/git/blobs/$_documentSha')) {
            return _json({'sha': _documentSha, 'size': 1, 'encoding': 'base64', 'content': content});
          }
          return _json({'message': 'not found'}, status: 404);
        },
      );

      for (final malformed in ['Z=g=', 'Zh==', 'Zm9v====', '__8=', 'Zg%3D%3D', 'Zg\r==', 'Zg= =']) {
        content = malformed;
        await expectLater(
          api.openCanvas(_destination(), snapshot, 'Invalid.canvas'),
          throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
          reason: 'Rejected $malformed',
        );
      }
    });

    test('refuses symlinks and oversized declared blobs before fetching', () async {
      final snapshot = GitHubSnapshot(
        commitSha: _commitSha,
        treeSha: _treeSha,
        entries: {
          'Maths.canvas': const GitHubTreeEntry(
            path: 'Maths.canvas',
            sha: _documentSha,
            type: 'blob',
            mode: '120000',
            size: 10,
          ),
        },
      );
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
          return _json({'message': 'unexpected'});
        },
      );
      await expectLater(api.openCanvas(_destination(), snapshot, 'Maths.canvas'), throwsA(isA<GitHubApiException>()));
    });

    test('rejects oversized declared canvas before requesting its blob', () async {
      var blobRequests = 0;
      final snapshot = GitHubSnapshot(
        commitSha: _commitSha,
        treeSha: _treeSha,
        entries: {
          'Maths.canvas': const GitHubTreeEntry(
            path: 'Maths.canvas',
            sha: _documentSha,
            type: 'blob',
            mode: '100644',
            size: canvasProjectMaximumBytes + 1,
          ),
        },
      );
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity();
          if (request.url.path.endsWith('/git/blobs/$_documentSha')) blobRequests++;
          return _json({'message': 'unexpected'});
        },
      );
      await expectLater(api.openCanvas(_destination(), snapshot, 'Maths.canvas'), throwsA(isA<GitHubApiException>()));
      expect(blobRequests, 0);
    });
  });

  group('pending-write status', () {
    test('confirms the pending document and every referenced attachment sha', () async {
      final confirmed = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _documentSha,
        attachmentShas: const {_imagePath: _imageSha},
        attachmentNames: const {_imagePath: _imagePath},
      );
      final pending = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {_imagePath: _blobSha},
        attachmentNames: const {_imagePath: _imagePath},
      );
      final requests = <http.Request>[];
      final api = _pendingCheckApi(
        [
          _treeEntry('Maths.canvas', _blobSha),
          _treeEntry(_imagePath, _blobSha),
        ],
        onRequest: requests.add,
      );

      final result = await api.checkPendingWrite(_destination(), tracking: confirmed, pendingTracking: pending);

      expect(identical(result, pending), isTrue);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    });

    test('recognizes unchanged same-path and old-path rename baselines for manual retry', () async {
      final samePath = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _documentSha,
        attachmentShas: const {},
        attachmentNames: const {},
      );
      final samePathPending = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {},
        attachmentNames: const {},
      );
      final renamePending = GitHubCanvasTracking(
        path: 'University/Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {},
        attachmentNames: const {},
      );

      final unchangedSamePath = await _pendingCheckApi([_treeEntry('Maths.canvas', _documentSha)]).checkPendingWrite(
        _destination(),
        tracking: samePath,
        pendingTracking: samePathPending,
      );
      final unchangedRename = await _pendingCheckApi([_treeEntry('Maths.canvas', _documentSha)]).checkPendingWrite(
        _destination(),
        tracking: samePath,
        pendingTracking: renamePending,
      );
      final confirmedRename = await _pendingCheckApi([
        _treeEntry('University/Maths.canvas', _blobSha),
      ]).checkPendingWrite(_destination(), tracking: samePath, pendingTracking: renamePending);

      expect(identical(unchangedSamePath, samePath), isTrue);
      expect(identical(unchangedRename, samePath), isTrue);
      expect(identical(confirmedRename, renamePending), isTrue);
    });

    test('allows a first-publication retry only when its document path is absent', () async {
      final pending = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {},
        attachmentNames: const {},
      );
      final result = await _pendingCheckApi(const []).checkPendingWrite(
        _destination(),
        pendingTracking: pending,
      );

      expect(result, isNull);
      await expectLater(
        _pendingCheckApi([_treeEntry('Maths.canvas/child.txt', _imageSha)]).checkPendingWrite(
          _destination(),
          pendingTracking: pending,
        ),
        throwsA(isA<GitHubConflict>()),
      );
    });

    test('rejects inconsistent persisted attachment metadata', () async {
      final malformed = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {_imagePath: _imageSha},
        attachmentNames: const {},
      );

      await expectLater(
        _pendingCheckApi([_treeEntry('Maths.canvas', _blobSha), _treeEntry(_imagePath, _imageSha)]).checkPendingWrite(
          _destination(),
          pendingTracking: malformed,
        ),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
      );
    });

    test('keeps ambiguous or partially matching remote states as conflicts', () async {
      final confirmed = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _documentSha,
        attachmentShas: const {},
        attachmentNames: const {},
      );
      final pendingMove = GitHubCanvasTracking(
        path: 'University/Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {},
        attachmentNames: const {},
      );
      final samePathPending = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {},
        attachmentNames: const {},
      );
      final pendingWithImage = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {_imagePath: _imageSha},
        attachmentNames: const {_imagePath: _imagePath},
      );

      for (final (tree, baseline, pending) in [
        (
          [_treeEntry('Maths.canvas', _documentSha), _treeEntry('University/Maths.canvas', _blobSha)],
          confirmed,
          pendingMove,
        ),
        (
          [_treeEntry('Maths.canvas', _documentSha), _treeEntry('University/Maths.canvas', _imageSha)],
          confirmed,
          pendingMove,
        ),
        (const <Map<String, Object?>>[], confirmed, samePathPending),
        ([_treeEntry('Maths.canvas', _blobSha), _treeEntry(_imagePath, _blobSha)], confirmed, pendingWithImage),
      ]) {
        await expectLater(
          _pendingCheckApi(tree).checkPendingWrite(_destination(), tracking: baseline, pendingTracking: pending),
          throwsA(isA<GitHubConflict>()),
        );
      }
    });

    test('retains repository identity, session, and rate-limit checks', () async {
      final requests = <String>[];
      final api = _api(
        github: (request) async {
          requests.add(request.url.path);
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repositoryIdentity(id: 99);
          return _json({'message': 'unexpected request'}, status: 404);
        },
      );
      final pending = GitHubCanvasTracking(
        path: 'Maths.canvas',
        documentSha: _blobSha,
        attachmentShas: const {},
        attachmentNames: const {},
      );

      await expectLater(
        api.checkPendingWrite(_destination(), pendingTracking: pending),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
      );

      expect(requests, ['/user', '/repos/owner/repo']);

      final expired = _api(
        github: (_) async => _json({'message': 'expired'}, status: 401),
      );
      await expectLater(
        expired.checkPendingWrite(_destination(), pendingTracking: pending),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.reconnect)),
      );

      var mediatorRequests = 0;
      var githubRequests = 0;
      final limited = _api(
        mediator: (request) async {
          mediatorRequests++;
          return await _defaultMediator(request);
        },
        github: (_) async {
          githubRequests++;
          return _json({'message': 'rate limited'}, status: 429, headers: {'retry-after': '60'});
        },
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          limited.checkPendingWrite(_destination(), pendingTracking: pending),
          throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.rateLimited)),
        );
      }
      expect(mediatorRequests, 1);
      expect(githubRequests, 1);
    });
  });

  group('commit', () {
    test('publishes only selected canvas over captured base tree and calls guard before ref update', () async {
      final treeBodies = <Map<String, dynamic>>[];
      final commitBodies = <Map<String, dynamic>>[];
      var patchCalled = false;
      String? refReadPath;
      String? refUpdatePath;
      Map<String, dynamic>? refUpdateBody;
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.method == 'GET' && request.url.path.contains('/git/ref/')) {
            refReadPath = request.url.path;
            if (request.url.path == '/repos/owner/repo/git/ref/heads/feature/release') return _ref();
          }
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': _treeEntries([
                (path: 'README.md', sha: _blobSha, type: 'blob', mode: '100644', size: 7),
                (path: 'Physics.canvas', sha: _documentSha, type: 'blob', mode: '100644', size: 20),
              ]),
            });
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) return _json({'sha': _blobSha});
          if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) {
            treeBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return _json({'sha': _treeSha});
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) {
            commitBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return _json({'sha': _documentSha, 'html_url': 'https://github.com/owner/repo/commit/$_documentSha'});
          }
          if (request.method == 'PATCH') {
            patchCalled = true;
            refUpdatePath = request.url.path;
            refUpdateBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'ref': 'refs/heads/main'});
          }
          return await _snapshotRoute(request, tree: const []);
        },
      );
      final result = await api.commitCanvas(
        destination: _destination(branch: 'feature/release'),
        path: 'Maths.canvas',
        project: _emptyProject(),
        message: 'docs: save canvas',
        beforeRefUpdate: (sha, tracking) async {
          expect(sha, _documentSha);
          expect(tracking.path, 'Maths.canvas');
          expect(patchCalled, isFalse);
        },
      );
      expect(result.noChanges, isFalse);
      expect(result.commitSha, _documentSha);
      expect(treeBodies.single['base_tree'], _treeSha);
      expect((treeBodies.single['tree'] as List).cast<Map<String, dynamic>>().map((entry) => entry['path']), [
        'Maths.canvas',
      ]);
      expect(commitBodies.single['message'], 'docs: save canvas');
      expect(commitBodies.single['parents'], [_commitSha]);
      expect(patchCalled, isTrue);
      expect(refReadPath, '/repos/owner/repo/git/ref/heads/feature/release');
      expect(refUpdatePath, '/repos/owner/repo/git/refs/heads/feature/release');
      expect(refUpdateBody?['force'], isFalse);
    });

    test('conflicts on tracked remote changes and does not write', () async {
      var writes = 0;
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': _treeEntries([
                (path: 'Maths.canvas', sha: _blobSha, type: 'blob', mode: '100644', size: 20),
              ]),
            });
          }
          if (request.method == 'POST' || request.method == 'PATCH') writes++;
          return await _snapshotRoute(request, tree: const []);
        },
      );
      await expectLater(
        api.commitCanvas(
          destination: _destination(),
          path: 'Maths.canvas',
          project: _emptyProject(),
          tracking: GitHubCanvasTracking(
            path: 'Maths.canvas',
            documentSha: _documentSha,
            attachmentShas: const {},
            attachmentNames: const {},
          ),
          message: 'docs: save canvas',
          beforeRefUpdate: (_, _) async {},
        ),
        throwsA(isA<GitHubConflict>().having((error) => error.path, 'path', 'Maths.canvas')),
      );
      expect(writes, 0);
    });

    test('returns no-op for identical tracked bytes', () async {
      final documentBytes = _emptyDocumentBytes();
      var writes = 0;
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': _treeEntries([
                (path: 'Maths.canvas', sha: _documentSha, type: 'blob', mode: '100644', size: documentBytes.length),
              ]),
            });
          }
          if (request.url.path.endsWith('/git/blobs/$_documentSha')) return _blob(_documentSha, documentBytes);
          if (request.method == 'POST' || request.method == 'PATCH') writes++;
          return await _snapshotRoute(request, tree: const []);
        },
      );
      final result = await api.commitCanvas(
        destination: _destination(),
        path: 'Maths.canvas',
        project: _emptyProject(),
        tracking: GitHubCanvasTracking(
          path: 'Maths.canvas',
          documentSha: _documentSha,
          attachmentShas: const {},
          attachmentNames: const {},
        ),
        message: 'docs: save canvas',
        beforeRefUpdate: (_, _) async {},
      );
      expect(result.noChanges, isTrue);
      expect(result.commitSha, isNull);
      expect(writes, 0);
    });

    test('moves only the tracked document and preserves unrelated repository files', () async {
      late Map<String, dynamic> treeBody;
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': _treeEntries([
                (path: 'Maths.canvas', sha: _documentSha, type: 'blob', mode: '100644', size: 10),
                (path: 'Physics.canvas', sha: _blobSha, type: 'blob', mode: '100644', size: 10),
                (path: 'README.md', sha: _imageSha, type: 'blob', mode: '100644', size: 7),
              ]),
            });
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) return _json({'sha': _blobSha});
          if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) {
            treeBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'sha': _treeSha});
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) return _json({'sha': _imageSha});
          if (request.method == 'PATCH') return _json({'ref': 'refs/heads/main'});
          return await _snapshotRoute(request, tree: const []);
        },
      );

      final result = await api.commitCanvas(
        destination: _destination(),
        path: 'University/Maths.canvas',
        project: _emptyProject(),
        tracking: GitHubCanvasTracking(
          path: 'Maths.canvas',
          documentSha: _documentSha,
          attachmentShas: const {},
          attachmentNames: const {},
        ),
        message: 'docs: move canvas',
        beforeRefUpdate: (_, tracking) async => expect(tracking.path, 'University/Maths.canvas'),
      );

      final entries = (treeBody['tree'] as List).cast<Map<String, dynamic>>();
      expect(result.noChanges, isFalse);
      expect(entries.map((entry) => entry['path']), containsAll(['University/Maths.canvas', 'Maths.canvas']));
      expect(entries.singleWhere((entry) => entry['path'] == 'Maths.canvas')['sha'], isNull);
      expect(entries.map((entry) => entry['path']), isNot(contains('Physics.canvas')));
      expect(entries.map((entry) => entry['path']), isNot(contains('README.md')));
    });

    test('allocates a fresh remote image path instead of overwriting different bytes', () async {
      final imageBytes = base64.decode(_png);
      final existingBytes = Uint8List.fromList(imageBytes)..[imageBytes.length - 1] ^= 1;
      final project = CanvasProject(
        document: CanvasDocument(
          background: CanvasBackgroundKind.dotGrid,
          elements: [MediaElementData(id: 'media-1', position: Offset.zero, width: 120, url: _imagePath)],
        ),
        attachments: {_imagePath: imageBytes},
      );
      final blobPosts = <Map<String, dynamic>>[];
      late Map<String, dynamic> treeBody;
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': _treeEntries([
                (
                  path: _imagePath,
                  sha: _imageSha,
                  type: 'blob',
                  mode: '100644',
                  size: existingBytes.length,
                ),
              ]),
            });
          }
          if (request.url.path.endsWith('/git/blobs/$_imageSha')) return _blob(_imageSha, existingBytes);
          if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) {
            blobPosts.add(jsonDecode(request.body) as Map<String, dynamic>);
            return _json({'sha': blobPosts.length == 1 ? _blobSha : _documentSha});
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) {
            treeBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'sha': _treeSha});
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) return _json({'sha': _commitSha});
          if (request.method == 'PATCH') return _json({'ref': 'refs/heads/main'});
          return await _snapshotRoute(request, tree: const []);
        },
      );

      final result = await api.commitCanvas(
        destination: _destination(),
        path: 'Maths.canvas',
        project: project,
        message: 'docs: update canvas',
        beforeRefUpdate: (_, tracking) async => expect(tracking.attachmentNames[_imagePath], isNot(_imagePath)),
      );

      final uploadedDocument = CanvasDocument.fromJson(
        jsonDecode(utf8.decode(base64.decode(blobPosts.last['content'] as String))),
      );
      final uploadedAttachmentPath = canvasAttachmentPaths(uploadedDocument).single;
      final treeEntries = (treeBody['tree'] as List).cast<Map<String, dynamic>>();
      expect(uploadedAttachmentPath, isNot(_imagePath));
      expect(project.document.elements.whereType<MediaElementData>().single.url, _imagePath);
      expect(result.tracking.attachmentShas.keys.single, uploadedAttachmentPath);
      expect(treeEntries.map((entry) => entry['path']), contains(uploadedAttachmentPath));
      expect(treeEntries.map((entry) => entry['path']), isNot(contains(_imagePath)));
    });

    test('reports uncertain final ref update with durable tracking', () async {
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({'truncated': false, 'tree': <Map<String, Object?>>[]});
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) return _json({'sha': _blobSha});
          if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) return _json({'sha': _treeSha});
          if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) {
            return _json({'sha': _documentSha});
          }
          if (request.method == 'PATCH') return _json({'message': 'server error'}, status: 500);
          return await _snapshotRoute(request, tree: const []);
        },
      );
      await expectLater(
        api.commitCanvas(
          destination: _destination(),
          path: 'Maths.canvas',
          project: _emptyProject(),
          message: 'docs: save canvas',
          beforeRefUpdate: (_, tracking) async => expect(tracking.path, 'Maths.canvas'),
        ),
        throwsA(
          isA<GitHubUnconfirmedCommit>()
              .having((error) => error.commitSha, 'commitSha', _documentSha)
              .having((error) => error.tracking.path, 'tracking.path', 'Maths.canvas'),
        ),
      );
    });

    test('treats a rejected non-fast-forward ref update as a definite conflict', () async {
      var guardSaved = false;
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({'truncated': false, 'tree': <Map<String, Object?>>[]});
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) return _json({'sha': _blobSha});
          if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) return _json({'sha': _treeSha});
          if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) {
            return _json({'sha': _documentSha});
          }
          if (request.method == 'PATCH') return _json({'message': 'non-fast-forward'}, status: 422);
          return await _snapshotRoute(request, tree: const []);
        },
      );

      await expectLater(
        api.commitCanvas(
          destination: _destination(),
          path: 'Maths.canvas',
          project: _emptyProject(),
          message: 'docs: save canvas',
          beforeRefUpdate: (_, _) async {
            guardSaved = true;
          },
        ),
        throwsA(isA<GitHubConflict>().having((error) => error.message, 'message', contains('branch changed'))),
      );
      expect(guardSaved, isTrue);
    });

    test('validates lowercase conventional subjects', () {
      expect(isValidGitHubCommitMessage('docs: save canvas'), isTrue);
      expect(isValidGitHubCommitMessage('Docs: save canvas'), isFalse);
      expect(isValidGitHubCommitMessage('docs: '), isFalse);
      expect(isValidGitHubCommitMessage('docs: save\ncanvas'), isFalse);
      expect(isValidGitHubCommitMessage('docs: ${List.filled(70, 'a').join()}'), isFalse);
    });
  });
}
