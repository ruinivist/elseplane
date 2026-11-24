import 'dart:convert';

import 'package:elseplane/github/github_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _mediator = 'https://mediator.example';

http.Response _json(Object? value, {int status = 200, Map<String, String> headers = const {}}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

http.Response _user({Map<String, String> headers = const {}}) => _json({'id': 1, 'login': 'owner'}, headers: headers);

Map<String, Object?> _installation({int id = 10, String login = 'owner', String? url}) => {
  'id': id,
  'account': {'id': id + 100, 'login': login},
  'html_url': url ?? 'https://github.com/settings/installations/$id',
  'permissions': {'contents': 'write'},
};

Map<String, Object?> _repository({
  required int id,
  required String owner,
  required String name,
  String branch = 'main',
  bool canPull = true,
  bool canPush = true,
}) => {
  'id': id,
  'owner': {'login': owner},
  'name': name,
  'full_name': '$owner/$name',
  'private': true,
  'default_branch': branch,
  'permissions': {'pull': canPull, 'push': canPush},
  'archived': false,
  'disabled': false,
};

Future<http.Response> _defaultMediator(http.Request request) async {
  if (request.method != 'POST' || request.body != '{}') return _json({'error': 'not found'}, status: 404);
  if (request.url.path == '/oauth/github/start') {
    return _json({'authorization_url': 'https://github.com/login/oauth/authorize?client_id=app'});
  }
  if (request.url.path == '/session/logout') return http.Response('', 204);
  if (request.url.path == '/oauth/github/token') {
    return _json({'access_token': 'secret-token', 'token_type': 'Bearer', 'scope': ''});
  }
  return _json({'error': 'not found'}, status: 404);
}

GitHubApi _api({
  required Future<http.Response> Function(http.Request request) github,
  Future<http.Response> Function(http.Request request)? mediator,
}) => GitHubApi(
  mediatorUrl: Uri.parse(_mediator),
  mediatorClient: MockClient(mediator ?? _defaultMediator),
  githubClient: MockClient(github),
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

    test('rejects unsafe authorization urls and accepts empty or omitted scopes', () async {
      final unsafe = _api(
        mediator: (request) async => _json({'authorization_url': 'https://github.com.evil.test/login/oauth/authorize'}),
        github: (_) async => _user(),
      );
      await expectLater(unsafe.startAuthorization(), throwsA(isA<GitHubApiException>()));

      for (final response in [
        _api(
          mediator: (_) async => _json({'access_token': 'secret-token', 'scope': ''}),
          github: (_) async => _user(),
        ),
        _api(
          mediator: (_) async => _json({'access_token': 'secret-token'}),
          github: (_) async => _user(headers: const {'x-oauth-scopes': ''}),
        ),
      ]) {
        expect((await response.account()).id, 1);
      }

      final malformed = _api(
        mediator: (_) async => _json({'access_token': 'secret-token', 'scope': 1}),
        github: (_) async => _user(),
      );
      await expectLater(
        malformed.account(),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
      );
    });

    test('repository resolution verifies selected installation membership and default branch', () async {
      const selected = GitHubRepository(
        installationId: 10,
        id: 2,
        owner: 'owner',
        name: 'repo',
        isPrivate: true,
        defaultBranch: 'main',
        canPull: true,
        canPush: true,
        archived: false,
        disabled: false,
      );
      final api = _api(
        github: (request) async {
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations/10/repositories') {
            expect(request.url.queryParameters, {'per_page': '100', 'page': '1'});
            return _json({
              'total_count': 1,
              'repositories': [_repository(id: 2, owner: 'owner', name: 'repo')],
            });
          }
          if (request.url.path == '/repos/owner/repo/git/ref/heads/main') {
            return _json({
              'object': {'type': 'commit', 'sha': 'a' * 40},
            });
          }
          return _json({'message': 'not found'}, status: 404);
        },
      );
      final destination = await api.resolveRepository(selected);
      expect(destination.branch, 'main');
      expect(destination.repositoryId, 2);
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

  group('repository discovery', () {
    test('loads every installation and repository page, deduplicates, and sorts results', () async {
      final requests = <http.Request>[];
      var tokenRequests = 0;
      final api = _api(
        mediator: (request) async {
          if (request.url.path == '/oauth/github/token') tokenRequests++;
          return await _defaultMediator(request);
        },
        github: (request) async {
          requests.add(request);
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations') {
            if (request.url.queryParameters['page'] == '1') {
              return _json(
                {
                  'total_count': 2,
                  'installations': [_installation()],
                },
                headers: {'link': '<https://api.github.com/user/installations?per_page=100&page=2>; rel="next"'},
              );
            }
            return _json({
              'total_count': 2,
              'installations': [
                _installation(
                  id: 20,
                  login: 'team',
                  url: 'https://github.com/organizations/team/settings/installations/20',
                ),
              ],
            });
          }
          if (request.url.path == '/user/installations/10/repositories') {
            if (request.url.queryParameters['page'] == '1') {
              return _json(
                {
                  'total_count': 3,
                  'repositories': [_repository(id: 2, owner: 'owner', name: 'zeta')],
                },
                headers: {
                  'link': '<https://api.github.com/user/installations/10/repositories?per_page=100&page=2>; rel="next"',
                },
              );
            }
            return _json({
              'total_count': 3,
              'repositories': [
                _repository(id: 2, owner: 'owner', name: 'zeta'),
                _repository(id: 3, owner: 'owner', name: 'alpha'),
              ],
            });
          }
          if (request.url.path == '/user/installations/20/repositories') {
            return _json({
              'total_count': 1,
              'repositories': [_repository(id: 4, owner: 'team', name: 'beta')],
            });
          }
          return _json({'error': 'unexpected request'}, status: 404);
        },
      );

      final result = await api.discoverRepositories();

      expect(tokenRequests, 1);
      expect(result.installations.map((item) => item.id), [10, 20]);
      expect(result.installations.last.managementUri.path, '/organizations/team/settings/installations/20');
      expect(result.installations.first.canWriteContents, isTrue);
      expect(result.repositories.map((item) => item.fullName), ['owner/alpha', 'owner/zeta', 'team/beta']);
      expect(result.repositories.map((item) => item.id), [3, 2, 4]);
      expect(() => result.repositories.add(result.repositories.first), throwsUnsupportedError);
      expect(requests, hasLength(6));
      for (final request in requests.where((request) => request.url.path != '/user')) {
        expect(request.url.host, 'api.github.com');
        expect(request.url.queryParameters['per_page'], '100');
        expect(request.headers['Authorization'], 'Bearer secret-token');
      }
    });

    test('rejects unsafe pagination URLs without sending credentials to them', () async {
      final requests = <http.Request>[];
      final api = _api(
        github: (request) async {
          requests.add(request);
          if (request.url.path == '/user') return _user();
          if (request.url.path == '/user/installations') {
            return _json(
              {
                'total_count': 2,
                'installations': [_installation()],
              },
              headers: {'link': '<https://evil.example/user/installations?per_page=100&page=2>; rel="next"'},
            );
          }
          fail('Pagination followed an untrusted URL');
        },
      );

      await expectLater(
        api.discoverRepositories(),
        throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.invalidData)),
      );
      expect(requests.map((request) => request.url.host), ['api.github.com', 'api.github.com']);
    });

    test('fails closed on malformed pages and later-page errors', () async {
      for (final failSecondPage in [false, true]) {
        final api = _api(
          github: (request) async {
            if (request.url.path == '/user') return _user();
            if (request.url.path == '/user/installations') {
              return _json({
                'total_count': 1,
                'installations': [_installation()],
              });
            }
            if (request.url.path == '/user/installations/10/repositories') {
              if (failSecondPage && request.url.queryParameters['page'] == '2') {
                return _json({'error': 'temporary'}, status: 500);
              }
              if (request.url.queryParameters['page'] == '1') {
                return _json(
                  {
                    'total_count': failSecondPage ? 2 : 1,
                    'repositories': [
                      if (failSecondPage)
                        _repository(id: 2, owner: 'owner', name: 'repo')
                      else
                        {..._repository(id: 2, owner: 'owner', name: 'repo'), 'permissions': 'bad'},
                    ],
                  },
                  headers: failSecondPage
                      ? {
                          'link': '<https://api.github.com/user/installations/10/repositories?per_page=100&page=2>; rel="next"',
                        }
                      : const {},
                );
              }
            }
            return _json({'error': 'unexpected request'}, status: 404);
          },
        );
        await expectLater(api.discoverRepositories(), throwsA(isA<GitHubApiException>()));
      }
    });
  });

  group('GitHub failures', () {
    test('403 scope and reset headers do not override permission denial', () async {
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
            headers: {
              'x-ratelimit-remaining': '10',
              'x-ratelimit-reset': reset,
              'x-accepted-oauth-scopes': 'repo',
              'x-oauth-scopes': '',
            },
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
              .having((error) => error.toString(), 'message', contains('Try again in')),
        ),
      );
    });

    test('a later explicit request reaches GitHub after a rate limit', () async {
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
              ? _json({'message': 'rate limited'}, status: 429, headers: {'retry-after': '60'})
              : _user();
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
                const Duration(seconds: 60),
              ),
        ),
      );
      expect((await api.account()).id, 1);
      expect((mediatorRequests, githubRequests), (2, 2));
    });

    test('uses a 60-second default when rate-limit timing is absent', () async {
      final api = _api(github: (_) async => _json({'message': 'rate limited'}, status: 429));

      await expectLater(
        api.account(),
        throwsA(
          isA<GitHubApiException>()
              .having(
                (error) => error.retryAfter,
                'retryAfter',
                predicate<Duration?>(
                  (delay) =>
                      delay != null && delay >= const Duration(seconds: 59) && delay <= const Duration(seconds: 60),
                ),
              )
              .having((error) => error.message, 'message', contains('Try again in a minute')),
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
              .having((error) => error.retryAfter, 'retryAfter', Duration.zero)
              .having((error) => error.message, 'message', 'GitHub rate limit reached. Try again.'),
        ),
      );
      expect((await api.account()).id, 1);
      expect(mediatorRequests, 2);
      expect(githubRequests, 2);
    });
  });

  test('validates only nonblank commit messages', () {
    expect(isValidGitHubCommitMessage('docs: save canvas'), isTrue);
    expect(isValidGitHubCommitMessage(''), isFalse);
    expect(isValidGitHubCommitMessage(' \n\t '), isFalse);
    expect(isValidGitHubCommitMessage('Fix: Save Canvas'), isTrue);
    expect(isValidGitHubCommitMessage('docs: save\ncanvas'), isTrue);
    expect(isValidGitHubCommitMessage('docs: ${List.filled(70, 'a').join()}'), isTrue);
  });
}
