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

http.Response _user({Map<String, String> headers = const {}}) => _json(
  {'id': 1, 'login': 'owner'},
  headers: {'x-oauth-scopes': 'repo, user:email', ...headers},
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

  test('validates lowercase conventional subjects', () {
    expect(isValidGitHubCommitMessage('docs: save canvas'), isTrue);
    expect(isValidGitHubCommitMessage('Docs: save canvas'), isFalse);
    expect(isValidGitHubCommitMessage('docs: '), isFalse);
    expect(isValidGitHubCommitMessage('docs: save\ncanvas'), isFalse);
    expect(isValidGitHubCommitMessage('docs: ${List.filled(70, 'a').join()}'), isFalse);
  });
}
