import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _mediatorUrl = 'https://mediator.example';
const _headSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _treeSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _nextTreeSha = 'cccccccccccccccccccccccccccccccccccccccc';
const _documentSha = 'aed2973e4b8a7ff1b30ff5c4751e5a2b38989e74';
const _imageSha = '1ccd5817b2e1e7c3adefd77769a761a207e1bc91';
const _commitSha = 'ffffffffffffffffffffffffffffffffffffffff';
const _secondCommitSha = '1111111111111111111111111111111111111111';
const _imagePath = 'Folder/attachments/123e4567-e89b-42d3-a456-426614174000.png';
const _secondImagePath = 'Other/attachments/123e4567-e89b-42d3-a456-426614174000.png';

GitHubDestination _destination({String branch = 'main', int accountId = 1}) => GitHubDestination(
  accountId: accountId,
  repositoryId: 2,
  owner: 'owner',
  repository: 'repo',
  branch: branch,
);

GitHubRepository _selectedRepository({String owner = 'owner', String name = 'repo', String branch = 'main'}) =>
    GitHubRepository(
      installationId: 10,
      id: 2,
      owner: owner,
      name: name,
      isPrivate: true,
      defaultBranch: branch,
      canPull: true,
      canPush: true,
      archived: false,
      disabled: false,
    );

http.Response _json(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json'},
);

final class _StreamingClient extends http.BaseClient {
  _StreamingClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _send(request);
}

http.Response _token(http.Request request) =>
    _json({'access_token': 'secret-token', 'token_type': 'Bearer', 'scope': ''});

http.Response _user() => _json({'id': 1, 'login': 'owner'});

Map<String, Object?> _repository({
  int id = 2,
  String branch = 'main',
  bool canPull = true,
  bool canPush = true,
  bool archived = false,
  bool disabled = false,
  String owner = 'owner',
  String name = 'repo',
}) => {
  'id': id,
  'name': name,
  'full_name': '$owner/$name',
  'owner': {'login': owner},
  'private': true,
  'default_branch': branch,
  'permissions': {'pull': canPull, 'push': canPush},
  'archived': archived,
  'disabled': disabled,
};

http.Response _membership({
  int id = 2,
  String branch = 'main',
  bool canPull = true,
  bool canPush = true,
  bool archived = false,
  bool disabled = false,
  String owner = 'owner',
  String name = 'repo',
}) => _json({
  'total_count': 1,
  'repositories': [
    _repository(
      id: id,
      branch: branch,
      canPull: canPull,
      canPush: canPush,
      archived: archived,
      disabled: disabled,
      owner: owner,
      name: name,
    ),
  ],
});

http.Response _ref([String sha = _headSha]) => _json({
  'object': {'type': 'commit', 'sha': sha},
});

http.Response _commitTree([String sha = _treeSha]) => _json({
  'tree': {'sha': sha},
});

List<Map<String, Object?>> _entries(List<({String path, String sha, String type, String mode, int? size})> entries) => [
  for (final entry in entries)
    {
      'path': entry.path,
      'sha': entry.sha,
      'type': entry.type,
      'mode': entry.mode,
      if (entry.size != null) 'size': entry.size,
    },
];

Map<String, Object?> _blobEntry(String path, String sha, int size) => {
  'path': path,
  'sha': sha,
  'type': 'blob',
  'mode': '100644',
  'size': size,
};

GitHubApi _api(Future<http.Response> Function(http.Request) github) => GitHubApi(
  mediatorUrl: Uri.parse(_mediatorUrl),
  mediatorClient: MockClient((request) async {
    if (request.url.path == '/oauth/github/token') return _token(request);
    return _json({'error': 'not found'}, status: 404);
  }),
  githubClient: MockClient(github),
);

Future<http.Response> _emptySnapshot(
  http.Request request, {
  String defaultBranch = 'main',
  int repositoryId = 2,
}) async {
  if (request.url.path == '/user') return _user();
  if (request.url.path == '/user/installations/10/repositories') {
    return _membership(id: repositoryId, branch: defaultBranch);
  }
  if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
  if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
  if (request.url.path.endsWith('/git/trees/$_treeSha')) {
    return _json({'truncated': false, 'tree': <Map<String, Object?>>[]});
  }
  return _json({'error': 'unexpected request'}, status: 404);
}

TransferTree _tree({bool withImage = true}) => TransferTree(
  files: {
    'Folder/Map.canvas.json': Uint8List.fromList([1, 2, 3]),
    if (withImage) _imagePath: Uint8List.fromList([4, 5]),
  },
  directories: const {'Folder'},
);

void main() {
  group('GitHub repository source', () {
    test('captures one head and lazily reads supported content by captured SHA', () async {
      final requests = <String>[];
      final blobReads = <String>[];
      final rawRequests = <http.Request>[];
      var currentHead = _headSha;
      const document = [1, 2, 3];
      final api = _api((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') return _membership();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref(currentHead);
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/commits/$_secondCommitSha')) return _commitTree(_nextTreeSha);
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({
            'truncated': false,
            'tree': _entries([
              (path: 'Folder/Map.canvas.json', sha: _documentSha, type: 'blob', mode: '100644', size: 3),
              (path: _imagePath, sha: _imageSha, type: 'blob', mode: '100644', size: 2),
              (path: 'README.md', sha: _commitSha, type: 'blob', mode: '100644', size: 4),
              (path: 'Folder', sha: _treeSha, type: 'tree', mode: '040000', size: null),
              (path: 'Folder/attachments', sha: _nextTreeSha, type: 'tree', mode: '040000', size: null),
            ]),
          });
        }
        if (request.url.path.contains('/git/blobs/')) {
          final sha = request.url.path.split('/').last;
          blobReads.add(sha);
          rawRequests.add(request);
          return http.Response.bytes(document, 200, headers: const {'content-type': 'application/octet-stream'});
        }
        return _json({'error': 'unexpected request'}, status: 404);
      });

      final source = await api.readRepository(_destination(), installationId: 10);
      currentHead = _secondCommitSha;
      final entries = await source.entries();
      expect(entries.map((entry) => (entry.path, entry.kind, entry.size)), [
        ('Folder/Map.canvas.json', TransferEntryKind.regularFile, 3),
        (_imagePath, TransferEntryKind.regularFile, 2),
        ('README.md', TransferEntryKind.regularFile, 4),
        ('Folder', TransferEntryKind.directory, null),
        ('Folder/attachments', TransferEntryKind.directory, null),
      ]);
      expect(
        () => entries.add(TransferEntry(path: 'other', kind: TransferEntryKind.regularFile)),
        throwsUnsupportedError,
      );
      final documentBytes = await source.read('Folder/Map.canvas.json');
      expect(documentBytes, document);
      expect(() => documentBytes[0] = 9, throwsUnsupportedError);
      await expectLater(source.read('README.md'), throwsA(isA<GitHubApiException>()));
      expect(blobReads, [_documentSha]);
      expect(rawRequests.single.headers['Accept'], 'application/vnd.github.raw+json');
      expect(rawRequests.single.headers['Authorization'], 'Bearer secret-token');
      expect(rawRequests.single.headers['X-GitHub-Api-Version'], '2022-11-28');
      expect(rawRequests.single.followRedirects, isFalse);
      expect(requests, [
        'GET /user',
        'GET /user/installations/10/repositories',
        'GET /repos/owner/repo/git/ref/heads/main',
        'GET /repos/owner/repo/git/commits/$_headSha',
        'GET /repos/owner/repo/git/trees/$_treeSha',
        'GET /repos/owner/repo/git/blobs/$_documentSha',
      ]);
    });

    test('independently checks account, repository identity, and saved default branch', () async {
      for (final mismatch in [
        (accountId: 1, repositoryId: 9, branch: 'main'),
        (accountId: 1, repositoryId: 2, branch: 'release'),
        (accountId: 9, repositoryId: 2, branch: 'main'),
      ]) {
        for (final action in ['read', 'commit']) {
          final requests = <String>[];
          final api = _api((request) async {
            requests.add(request.url.path);
            if (request.url.path == '/user') return _user();
            if (request.url.path == '/user/installations/10/repositories') {
              return _membership(id: mismatch.repositoryId, branch: mismatch.branch);
            }
            return _json({'error': 'must not proceed'}, status: 404);
          });
          final destination = _destination(accountId: mismatch.accountId);
          if (action == 'read') {
            await expectLater(api.readRepository(destination, installationId: 10), throwsA(isA<GitHubApiException>()));
          } else {
            await expectLater(
              api.commitTransfer(destination, _tree(), installationId: 10, message: 'docs: save transfer'),
              throwsA(isA<GitHubApiException>()),
            );
          }
          expect(requests, [
            '/user',
            if (mismatch.accountId == 1) '/user/installations/10/repositories',
          ]);
        }
      }
    });

    test('requires selected installation membership and never falls back to a public repository request', () async {
      for (final action in ['read', 'commit']) {
        final requests = <String>[];
        final api = _api((request) async {
          requests.add(request.url.path);
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') {
            return _json({'total_count': 0, 'repositories': <Object?>[]});
          }
          return _json({'message': 'not found'}, status: 404);
        });
        if (action == 'read') {
          await expectLater(
            api.readRepository(_destination(), installationId: 10),
            throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.permissionDenied)),
          );
        } else {
          await expectLater(
            api.commitTransfer(_destination(), _tree(), installationId: 10, message: 'docs: save transfer'),
            throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.permissionDenied)),
          );
        }
        expect(requests, ['/user', '/user/installations/10/repositories']);
        expect(requests, isNot(contains('/repos/owner/repo')));
      }
    });

    test('rejects renamed repositories before branch access', () async {
      final requests = <String>[];
      final api = _api((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') {
          return _membership(name: 'renamed');
        }
        return _json({'error': 'must not proceed'}, status: 404);
      });

      await expectLater(
        api.readRepository(_destination(), installationId: 10),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
      );
      expect(requests, ['/user', '/user/installations/10/repositories']);
    });

    test('allows read-only repositories for import but blocks commits before writes', () async {
      final readApi = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') return _membership(canPush: false);
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({'truncated': false, 'tree': <Map<String, Object?>>[]});
        }
        return _json({'error': 'unexpected request'}, status: 404);
      });
      await expectLater(readApi.readRepository(_destination(), installationId: 10), completes);

      for (final status in [
        (canPush: false, archived: false, disabled: false),
        (canPush: true, archived: true, disabled: false),
        (canPush: true, archived: false, disabled: true),
      ]) {
        var writes = 0;
        final api = _api((request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') {
            return _membership(canPush: status.canPush, archived: status.archived, disabled: status.disabled);
          }
          if (request.method == 'POST' || request.method == 'PATCH') writes++;
          return _json({'error': 'must not proceed'}, status: 404);
        });
        await expectLater(
          api.commitTransfer(_destination(), _tree(), installationId: 10, message: 'docs: save transfer'),
          throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.permissionDenied)),
        );
        expect(writes, 0);
      }
    });

    test('confirms empty repositories through an empty bounded branches response only', () async {
      for (final action in ['resolve', 'read', 'commit']) {
        var writes = 0;
        final api = _api((request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') return _membership();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _json({'message': 'not found'}, status: 404);
          if (request.url.path == '/repos/owner/repo/branches') {
            expect(request.url.queryParameters, {'per_page': '1'});
            return _json(<Object?>[]);
          }
          if (request.method == 'POST' || request.method == 'PATCH') writes++;
          return _json({'message': 'unexpected request'}, status: 404);
        });
        final operation = switch (action) {
          'resolve' => api.resolveRepository(_selectedRepository()),
          'read' => api.readRepository(_destination(), installationId: 10),
          _ => api.commitTransfer(_destination(), _tree(), installationId: 10, message: 'docs: save transfer'),
        };
        await expectLater(
          operation,
          throwsA(
            isA<GitHubApiException>()
                .having((error) => error.kind, 'kind', GitHubErrorKind.emptyRepository)
                .having(
                  (error) => error.message,
                  'message',
                  'This repository is empty. Add a README on GitHub, then refresh.',
                ),
          ),
        );
        expect(writes, 0);
      }
    });

    test('does not infer emptiness from generic branch failures or a populated branches response', () async {
      for (final branchStatus in [403, 404]) {
        final api = _api((request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') return _membership();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _json({'message': 'not found'}, status: 404);
          if (request.url.path == '/repos/owner/repo/branches') {
            return _json({'message': 'failure'}, status: branchStatus);
          }
          return _json({'error': 'unexpected request'}, status: 404);
        });
        await expectLater(
          api.readRepository(_destination(), installationId: 10),
          throwsA(
            isA<GitHubApiException>().having(
              (error) => error.kind,
              'kind',
              branchStatus == 403 ? GitHubErrorKind.permissionDenied : GitHubErrorKind.missingResource,
            ),
          ),
        );
      }

      final populated = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') return _membership();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _json({'message': 'not found'}, status: 409);
        if (request.url.path == '/repos/owner/repo/branches') {
          return _json([
            {'name': 'other'},
          ]);
        }
        return _json({'error': 'unexpected request'}, status: 404);
      });
      await expectLater(
        populated.readRepository(_destination(), installationId: 10),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.conflict)),
      );
    });

    test('shares one raw immutable read for normalized blob aliases', () async {
      const bytes = [4, 5];
      final blobReads = <String>[];
      final api = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') return _membership();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({
            'truncated': false,
            'tree': _entries([
              (path: _imagePath, sha: _imageSha.toUpperCase(), type: 'blob', mode: '100644', size: 2),
              (path: _secondImagePath, sha: _imageSha, type: 'blob', mode: '100644', size: 2),
              (path: '.git/config', sha: _imageSha, type: 'blob', mode: '100644', size: null),
            ]),
          });
        }
        if (request.url.path.contains('/git/blobs/')) {
          blobReads.add(request.url.path.split('/').last);
          return http.Response.bytes(bytes, 200);
        }
        return _json({'error': 'unexpected request'}, status: 404);
      });
      final source = await api.readRepository(_destination(), installationId: 10);
      final results = await Future.wait([source.read(_imagePath), source.read(_secondImagePath)]);

      expect(results, [bytes, bytes]);
      expect(identical(results[0], results[1]), isTrue);
      expect(() => results.first[0] = 9, throwsUnsupportedError);
      expect(blobReads, [_imageSha.toUpperCase()]);
    });

    test('rejects inconsistent known sizes for a blob before any blob GET', () async {
      var blobReads = 0;
      final api = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') return _membership();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({
            'truncated': false,
            'tree': [
              _blobEntry('Map.canvas.json', _documentSha, 3),
              _blobEntry('Copy.canvas.json', _documentSha.toUpperCase(), 4),
            ],
          });
        }
        if (request.url.path.contains('/git/blobs/')) blobReads++;
        return _json({'error': 'unexpected request'}, status: 404);
      });

      await expectLater(
        api.readRepository(_destination(), installationId: 10),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
      );
      expect(blobReads, 0);
    });

    test('rejects oversized, short, and wrong-content raw blob responses', () async {
      for (final failure in [
        (name: 'oversized', bytes: <int>[1, 2, 3, 4]),
        (name: 'short', bytes: <int>[1, 2]),
        (name: 'wrong-content', bytes: <int>[3, 2, 1]),
      ]) {
        final api = _api((request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') return _membership();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
          if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': [_blobEntry('Map.canvas.json', _documentSha, 3)],
            });
          }
          if (request.url.path.endsWith('/git/blobs/$_documentSha')) {
            return http.Response.bytes(failure.bytes, 200);
          }
          return _json({'error': 'unexpected request'}, status: 404);
        });
        final source = await api.readRepository(_destination(), installationId: 10);

        await expectLater(
          source.read('Map.canvas.json'),
          throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
          reason: failure.name,
        );
      }
    });

    test('classifies a nonempty zero-byte 429 without waiting for body cleanup', () async {
      var cleanupCalled = false;
      final normalClient = MockClient((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') return _membership();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({
            'truncated': false,
            'tree': [_blobEntry('Map.canvas.json', _documentSha, 0)],
          });
        }
        return _json({'error': 'unexpected request'}, status: 404);
      });
      final client = _StreamingClient((request) async {
        if (request.url.path.endsWith('/git/blobs/$_documentSha')) {
          late final StreamController<List<int>> body;
          body = StreamController<List<int>>(
            onListen: () => body.add([1]),
            onCancel: () {
              cleanupCalled = true;
              return Future<void>.error(StateError('cleanup failed'));
            },
          );
          return http.StreamedResponse(
            body.stream,
            429,
            request: request,
            headers: const {'retry-after': '9'},
          );
        }
        return await normalClient.send(request);
      });
      final api = GitHubApi(
        mediatorUrl: Uri.parse(_mediatorUrl),
        mediatorClient: MockClient((request) async {
          if (request.url.path == '/oauth/github/token') return _token(request);
          return _json({'error': 'not found'}, status: 404);
        }),
        githubClient: client,
      );
      final source = await api.readRepository(_destination(), installationId: 10);

      await expectLater(
        source.read('Map.canvas.json'),
        throwsA(
          isA<GitHubApiException>()
              .having((error) => error.kind, 'kind', GitHubErrorKind.rateLimited)
              .having((error) => error.retryAfter, 'retryAfter', const Duration(seconds: 9)),
        ),
      );
      expect(cleanupCalled, isTrue);
    });

    test('rejects unsafe tree paths and oversized declared images before blob reads', () async {
      for (final path in [
        '/Map.canvas.json',
        'Folder//Map.canvas.json',
        '../Map.canvas.json',
        r'Folder\Map.canvas.json',
      ]) {
        var blobReads = 0;
        final api = _api((request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') return _membership();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
          if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': [_blobEntry(path, _documentSha, 1)],
            });
          }
          if (request.url.path.contains('/git/blobs/')) blobReads++;
          return _json({'error': 'unexpected request'}, status: 404);
        });

        await expectLater(api.readRepository(_destination(), installationId: 10), throwsA(isA<GitHubApiException>()));
        expect(blobReads, 0, reason: path);
      }

      var blobReads = 0;
      final imageApi = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') return _membership();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({
            'truncated': false,
            'tree': [_blobEntry(_imagePath, _imageSha, 10 * 1024 * 1024 + 1)],
          });
        }
        if (request.url.path.contains('/git/blobs/')) blobReads++;
        return _json({'error': 'unexpected request'}, status: 404);
      });
      await expectLater(
        imageApi.readRepository(_destination(), installationId: 10),
        throwsA(isA<GitHubApiException>()),
      );
      expect(blobReads, 0);
    });

    test('rejects truncated, unsupported, and over-budget tree metadata before blob reads', () async {
      for (final body in [
        {'truncated': true, 'tree': <Map<String, Object?>>[]},
        {
          'truncated': false,
          'tree': _entries([
            (path: 'link.canvas.json', sha: _documentSha, type: 'blob', mode: '120000', size: 1),
          ]),
        },
        {
          'truncated': false,
          'tree': _entries([
            (path: 'README.md', sha: _documentSha, type: 'blob', mode: '100644', size: 100 * 1024 * 1024),
            (path: 'LICENSE', sha: _imageSha, type: 'blob', mode: '100644', size: 41 * 1024 * 1024),
          ]),
        },
      ]) {
        var blobReads = 0;
        final api = _api((request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') return _membership();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
          if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) return _json(body);
          if (request.url.path.contains('/git/blobs/')) blobReads++;
          return _json({'error': 'unexpected request'}, status: 404);
        });
        await expectLater(api.readRepository(_destination(), installationId: 10), throwsA(isA<GitHubApiException>()));
        expect(blobReads, 0);
      }
    });
  });

  group('GitHub transfer commit', () {
    const documentBlobId = 'aed2973e4b8a7ff1b30ff5c4751e5a2b38989e74';
    const imageBlobId = '1ccd5817b2e1e7c3adefd77769a761a207e1bc91';

    for (final exactCopy in [false, true]) {
      test('publishes ${exactCopy ? 'an exact copy without uploads' : 'an edit with one upload'}', () async {
        final requestOrder = <String>[];
        final blobBodies = <Map<String, dynamic>>[];
        final message = '  Release: Save MixedCase Canvas\n${List.filled(80, 'x').join()}  ';
        late Map<String, dynamic> treeBody;
        late Map<String, dynamic> commitBody;
        late Map<String, dynamic> refBody;
        final api = _api((request) async {
          requestOrder.add('${request.method} ${request.url.path}');
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') return _membership();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
          if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': _entries([
                (path: 'README.md', sha: _commitSha, type: 'blob', mode: '100644', size: 12),
                (path: 'Folder', sha: _treeSha, type: 'tree', mode: '040000', size: null),
                (path: 'Folder/attachments', sha: _nextTreeSha, type: 'tree', mode: '040000', size: null),
                (
                  path: exactCopy ? 'Original.canvas.json' : 'Folder/Map.canvas.json',
                  sha: exactCopy ? documentBlobId : '7b54d3b14da13cb4f132fe0ce5063b4ba72df77e',
                  type: 'blob',
                  mode: '100644',
                  size: 3,
                ),
                (path: _imagePath, sha: imageBlobId.toUpperCase(), type: 'blob', mode: '100644', size: 2),
              ]),
            });
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) {
            blobBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return _json({'sha': documentBlobId});
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) {
            treeBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'sha': _nextTreeSha});
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) {
            commitBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'sha': _commitSha, 'html_url': 'https://github.com/owner/repo/commit/$_commitSha'});
          }
          if (request.method == 'PATCH') {
            refBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'ref': 'refs/heads/main'});
          }
          if (request.url.path.contains('/git/blobs/')) {
            fail('Commit must not read existing blob content');
          }
          return _json({'error': 'unexpected request'}, status: 404);
        });

        final result = await api.commitTransfer(
          _destination(),
          _tree(),
          installationId: 10,
          message: message,
        );

        expect(result.commitSha, _commitSha);
        expect(result.url, 'https://github.com/owner/repo/commit/$_commitSha');
        expect(blobBodies, [
          if (!exactCopy)
            {
              'content': base64.encode([1, 2, 3]),
              'encoding': 'base64',
            },
        ]);
        expect(treeBody['base_tree'], _treeSha);
        expect(treeBody['tree'], [
          {'path': 'Folder/Map.canvas.json', 'mode': '100644', 'type': 'blob', 'sha': documentBlobId},
          {'path': _imagePath, 'mode': '100644', 'type': 'blob', 'sha': imageBlobId},
        ]);
        expect(commitBody['message'], message);
        expect(commitBody['parents'], [_headSha]);
        expect(refBody, {'sha': _commitSha, 'force': false});
        expect(requestOrder, [
          'GET /user',
          'GET /user/installations/10/repositories',
          'GET /repos/owner/repo/git/ref/heads/main',
          'GET /repos/owner/repo/git/commits/$_headSha',
          'GET /repos/owner/repo/git/trees/$_treeSha',
          if (!exactCopy) 'POST /repos/owner/repo/git/blobs',
          'POST /repos/owner/repo/git/trees',
          'POST /repos/owner/repo/git/commits',
          'PATCH /repos/owner/repo/git/refs/heads/main',
        ]);
      });
    }

    test('rejects blank messages before making network requests', () async {
      var mediatorRequests = 0;
      var githubRequests = 0;
      final api = GitHubApi(
        mediatorUrl: Uri.parse(_mediatorUrl),
        mediatorClient: MockClient((request) async {
          mediatorRequests++;
          return _token(request);
        }),
        githubClient: MockClient((request) async {
          githubRequests++;
          return await _emptySnapshot(request);
        }),
      );

      for (final message in ['', ' \n\t ']) {
        await expectLater(
          api.commitTransfer(_destination(), _tree(), installationId: 10, message: message),
          throwsA(
            isA<GitHubApiException>().having(
              (error) => error.message,
              'message',
              'A commit message is required.',
            ),
          ),
        );
      }
      expect(mediatorRequests, 0);
      expect(githubRequests, 0);
    });

    test('rejects conflicting output and reserved attachments paths before upload', () async {
      for (final entry in [
        _blobEntry('Folder', _documentSha, 4),
        {
          'path': 'Folder/Map.canvas.json',
          'sha': _treeSha,
          'type': 'tree',
          'mode': '040000',
        },
        _blobEntry('Folder/attachments', _documentSha, 4),
      ]) {
        var blobPosts = 0;
        final conflictPath = entry['path']! as String;
        final api = _api((request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') return _membership();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
          if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({
              'truncated': false,
              'tree': [entry],
            });
          }
          if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) blobPosts++;
          return _json({'sha': _commitSha});
        });

        await expectLater(
          api.commitTransfer(_destination(), _tree(), installationId: 10, message: 'docs: save transfer'),
          throwsA(isA<GitHubConflict>().having((error) => error.path, 'path', conflictPath)),
        );
        expect(blobPosts, 0);
      }
    });

    test('reports uncertain branch updates with the commit link', () async {
      var blobPosts = 0;
      final api = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/user/installations/10/repositories') return _membership();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({'truncated': false, 'tree': <Map<String, Object?>>[]});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) {
          blobPosts++;
          return _json({'sha': blobPosts == 1 ? _documentSha : _imageSha});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/trees')) return _json({'sha': _nextTreeSha});
        if (request.method == 'POST' && request.url.path.endsWith('/git/commits')) {
          return _json({'sha': _secondCommitSha});
        }
        if (request.method == 'PATCH') return _json({'error': 'temporary'}, status: 500);
        return _json({'error': 'unexpected request'}, status: 404);
      });

      await expectLater(
        api.commitTransfer(_destination(), _tree(), installationId: 10, message: 'docs: save transfer'),
        throwsA(
          isA<GitHubUnconfirmedCommit>()
              .having((error) => error.sha, 'sha', _secondCommitSha)
              .having((error) => error.url, 'url', contains('/commit/$_secondCommitSha')),
        ),
      );
      expect(blobPosts, 2);
    });

    test('rejects non-transfer output before session or repository requests', () async {
      var requests = 0;
      final api = _api((request) async {
        requests++;
        return await _emptySnapshot(request);
      });
      await expectLater(
        api.commitTransfer(
          _destination(),
          TransferTree(
            files: {
              'README.md': Uint8List.fromList([1]),
            },
          ),
          installationId: 10,
          message: 'docs: save transfer',
        ),
        throwsA(isA<GitHubApiException>()),
      );
      expect(requests, 0);
    });
  });
}
