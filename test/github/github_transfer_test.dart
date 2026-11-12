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
const _documentSha = 'dddddddddddddddddddddddddddddddddddddddd';
const _imageSha = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _commitSha = 'ffffffffffffffffffffffffffffffffffffffff';
const _secondCommitSha = '1111111111111111111111111111111111111111';
const _imagePath = 'Folder/attachments/123e4567-e89b-42d3-a456-426614174000.png';

GitHubDestination _destination({String branch = 'main', int accountId = 1}) => GitHubDestination(
  accountId: accountId,
  repositoryId: 2,
  owner: 'owner',
  repository: 'repo',
  branch: branch,
);

http.Response _json(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json'},
);

http.Response _token(http.Request request) =>
    _json({'access_token': 'secret-token', 'token_type': 'Bearer', 'scope': 'repo'});

http.Response _user() => _json({'id': 1, 'login': 'owner'});

http.Response _repository({int id = 2, String branch = 'main'}) => _json({
  'id': id,
  'default_branch': branch,
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
  if (request.url.path == '/repos/owner/repo') {
    return _repository(id: repositoryId, branch: defaultBranch);
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
      var currentHead = _headSha;
      const document = [1, 2, 3];
      final api = _api((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/repos/owner/repo') return _repository();
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
          return _json({
            'sha': sha,
            'size': document.length,
            'encoding': 'base64',
            'content': base64.encode(document),
          });
        }
        return _json({'error': 'unexpected request'}, status: 404);
      });

      final source = await api.readRepository(_destination());
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
      expect(requests, [
        'GET /user',
        'GET /repos/owner/repo',
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
            if (request.url.path == '/repos/owner/repo') {
              return _repository(id: mismatch.repositoryId, branch: mismatch.branch);
            }
            return _json({'error': 'must not proceed'}, status: 404);
          });
          final destination = _destination(accountId: mismatch.accountId);
          if (action == 'read') {
            await expectLater(api.readRepository(destination), throwsA(isA<GitHubApiException>()));
          } else {
            await expectLater(
              api.commitTransfer(destination, _tree(), message: 'docs: save transfer'),
              throwsA(isA<GitHubApiException>()),
            );
          }
          expect(requests, [
            '/user',
            if (mismatch.accountId == 1) '/repos/owner/repo',
          ]);
        }
      }
    });

    test('bounds a lazy blob response from its declared size', () async {
      final api = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/repos/owner/repo') return _repository();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({
            'truncated': false,
            'tree': [_blobEntry('Map.canvas.json', _documentSha, 3)],
          });
        }
        if (request.url.path.endsWith('/git/blobs/$_documentSha')) {
          final response = _json({
            'sha': _documentSha,
            'size': 3,
            'encoding': 'base64',
            'content': base64.encode([1, 2, 3]),
          });
          return http.Response(response.body.padRight(300_000), 200, headers: response.headers);
        }
        return _json({'error': 'unexpected request'}, status: 404);
      });
      final source = await api.readRepository(_destination());

      await expectLater(source.read('Map.canvas.json'), throwsA(isA<GitHubApiException>()));
    });

    test('rejects malformed and noncanonical base64 blob content', () async {
      var content = '';
      final api = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/repos/owner/repo') return _repository();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({'truncated': false, 'tree': [_blobEntry('Map.canvas.json', _documentSha, 1)]});
        }
        if (request.url.path.endsWith('/git/blobs/$_documentSha')) {
          return _json({'sha': _documentSha, 'size': 1, 'encoding': 'base64', 'content': content});
        }
        return _json({'error': 'unexpected request'}, status: 404);
      });
      final source = await api.readRepository(_destination());

      for (final malformed in ['Z=g=', 'Zh==', 'Zm9v====', '__8=', 'Zg%3D%3D', 'Zg\r==', 'Zg= =']) {
        content = malformed;
        await expectLater(
          source.read('Map.canvas.json'),
          throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
          reason: 'Rejected $malformed',
        );
      }
    });

    test('rejects unsafe tree paths and oversized declared images before blob reads', () async {
      for (final path in ['/Map.canvas.json', 'Folder//Map.canvas.json', '../Map.canvas.json', r'Folder\Map.canvas.json']) {
        var blobReads = 0;
        final api = _api((request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/repos/owner/repo') return _repository();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
          if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) {
            return _json({'truncated': false, 'tree': [_blobEntry(path, _documentSha, 1)]});
          }
          if (request.url.path.contains('/git/blobs/')) blobReads++;
          return _json({'error': 'unexpected request'}, status: 404);
        });

        await expectLater(api.readRepository(_destination()), throwsA(isA<GitHubApiException>()));
        expect(blobReads, 0, reason: path);
      }

      var blobReads = 0;
      final imageApi = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/repos/owner/repo') return _repository();
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
      await expectLater(imageApi.readRepository(_destination()), throwsA(isA<GitHubApiException>()));
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
          if (request.url.path == '/repos/owner/repo') return _repository();
          if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
          if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
          if (request.url.path.endsWith('/git/trees/$_treeSha')) return _json(body);
          if (request.url.path.contains('/git/blobs/')) blobReads++;
          return _json({'error': 'unexpected request'}, status: 404);
        });
        await expectLater(api.readRepository(_destination()), throwsA(isA<GitHubApiException>()));
        expect(blobReads, 0);
      }
    });
  });

  group('GitHub transfer commit', () {
    test('preflights then uploads, creates one tree and commit, and updates once without force', () async {
      final requestOrder = <String>[];
      final blobBodies = <Map<String, dynamic>>[];
      late Map<String, dynamic> treeBody;
      late Map<String, dynamic> commitBody;
      late Map<String, dynamic> refBody;
      final api = _api((request) async {
        requestOrder.add('${request.method} ${request.url.path}');
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/repos/owner/repo') return _repository();
        if (request.url.path.endsWith('/git/ref/heads/main')) return _ref();
        if (request.url.path.endsWith('/git/commits/$_headSha')) return _commitTree();
        if (request.url.path.endsWith('/git/trees/$_treeSha')) {
          return _json({
            'truncated': false,
            'tree': _entries([
              (path: 'README.md', sha: _commitSha, type: 'blob', mode: '100644', size: 12),
              (path: 'Folder', sha: _treeSha, type: 'tree', mode: '040000', size: null),
              (path: 'Folder/attachments', sha: _nextTreeSha, type: 'tree', mode: '040000', size: null),
              (path: 'Folder/Map.canvas.json', sha: _documentSha, type: 'blob', mode: '100644', size: 10),
              (path: _imagePath, sha: _imageSha, type: 'blob', mode: '100644', size: 1),
            ]),
          });
        }
        if (request.method == 'POST' && request.url.path.endsWith('/git/blobs')) {
          blobBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _json({'sha': blobBodies.length == 1 ? _documentSha : _imageSha});
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

      final result = await api.commitTransfer(_destination(), _tree(), message: 'docs: save transfer');

      expect(result.commitSha, _commitSha);
      expect(result.url, 'https://github.com/owner/repo/commit/$_commitSha');
      expect(blobBodies, [
        {
          'content': base64.encode([1, 2, 3]),
          'encoding': 'base64',
        },
        {
          'content': base64.encode([4, 5]),
          'encoding': 'base64',
        },
      ]);
      expect(treeBody['base_tree'], _treeSha);
      expect((treeBody['tree'] as List).cast<Map<String, dynamic>>().map((entry) => entry['path']), [
        'Folder/Map.canvas.json',
        _imagePath,
      ]);
      expect((treeBody['tree'] as List).cast<Map<String, dynamic>>().every((entry) => entry['sha'] != null), isTrue);
      expect(commitBody['message'], 'docs: save transfer');
      expect(commitBody['parents'], [_headSha]);
      expect(refBody, {'sha': _commitSha, 'force': false});
      expect(requestOrder.where((request) => request.startsWith('PATCH ')), hasLength(1));
      expect(requestOrder.where((request) => request.contains('/git/blobs/')), isEmpty);
      expect(requestOrder.where((request) => request.contains('/git/blobs')), hasLength(2));
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
          if (request.url.path == '/repos/owner/repo') return _repository();
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
          api.commitTransfer(_destination(), _tree(), message: 'docs: save transfer'),
          throwsA(isA<GitHubConflict>().having((error) => error.path, 'path', conflictPath)),
        );
        expect(blobPosts, 0);
      }
    });

    test('reports uncertain branch updates with the commit link', () async {
      var blobPosts = 0;
      final api = _api((request) async {
        if (request.url.path == '/user') return _user();
        if (request.url.path == '/repos/owner/repo') return _repository();
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
        api.commitTransfer(_destination(), _tree(), message: 'docs: save transfer'),
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
          message: 'docs: save transfer',
        ),
        throwsA(isA<GitHubApiException>()),
      );
      expect(requests, 0);
    });
  });
}
