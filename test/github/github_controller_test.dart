import 'dart:async';
import 'dart:convert';

import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/github/github_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('restores a session and keeps failed logout disabled for retry', () async {
    var failLogout = true;
    final mediator = MockClient((request) async {
      if (request.url.path == '/oauth/github/token') {
        return _json({'access_token': 'not-for-storage', 'scope': ''});
      }
      if (request.url.path == '/session/logout') {
        return failLogout ? _json({'error': 'private response'}, status: 500) : http.Response('', 204);
      }
      return _json({'error': 'not found'}, status: 404);
    });
    final github = MockClient((request) async {
      if (request.url.path == '/user') return _json({'id': 17, 'login': 'canvas-user'});
      if (request.url.path == '/user/installations') return _json({'total_count': 0, 'installations': <Object?>[]});
      fail('Unexpected request ${request.url}');
    });
    final controller = GitHubController(
      GitHubApi(
        mediatorUrl: Uri.parse('https://mediator.example'),
        mediatorClient: mediator,
        githubClient: github,
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(mediator.close);
    addTearDown(github.close);

    await controller.restoreSession();
    expect(controller.account?.login, 'canvas-user');
    expect(controller.busy, isFalse);
    expect(controller.logoutNeedsRetry, isFalse);

    await expectLater(controller.logout(), throwsA(isA<GitHubApiException>()));
    expect(controller.account, isNull);
    expect(controller.logoutNeedsRetry, isTrue);
    expect(controller.error, isNot(contains('private response')));
    expect(controller.busy, isFalse);

    failLogout = false;
    await controller.logout();
    expect(controller.logoutNeedsRetry, isFalse);
    expect(controller.error, isNull);
  });

  test('only reconnect failures clear the account during run', () async {
    int? githubStatus;
    final mediator = MockClient((request) async {
      if (request.url.path == '/oauth/github/token') {
        return _json({'access_token': 'test-token'});
      }
      return _json({'error': 'not found'}, status: 404);
    });
    final github = MockClient((request) async {
      if (request.url.path == '/user/installations') return _json({'total_count': 0, 'installations': <Object?>[]});
      if (githubStatus case final status?) {
        return _json(
          {'message': 'failure'},
          status: status,
          headers: const {'x-accepted-oauth-scopes': 'repo', 'x-oauth-scopes': ''},
        );
      }
      return _json({'id': 17, 'login': 'canvas-user'});
    });
    final controller = GitHubController(
      GitHubApi(
        mediatorUrl: Uri.parse('https://mediator.example'),
        mediatorClient: mediator,
        githubClient: github,
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(mediator.close);
    addTearDown(github.close);

    await controller.restoreSession();
    controller.error = 'stale error';
    await expectLater(controller.run(() async => 'complete'), completion('complete'));
    expect(controller.error, isNull);

    githubStatus = 403;
    await expectLater(
      controller.run(controller.api.account),
      throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.permissionDenied)),
    );
    expect(controller.account?.login, 'canvas-user');
    expect(controller.error, isNull);

    githubStatus = 401;
    await expectLater(
      controller.run(controller.api.account),
      throwsA(isA<GitHubApiException>().having((error) => error.kind, 'kind', GitHubErrorKind.reconnect)),
    );
    expect(controller.account, isNull);
    expect(controller.error, 'Reconnect GitHub to continue.');
    expect(controller.logoutNeedsRetry, isFalse);
    expect(controller.busy, isFalse);
  });

  test('checks restoration without a destination and treats a missing session as disconnected', () async {
    var requests = 0;
    final mediator = MockClient((_) async {
      requests++;
      return _json({'error': 'no session'}, status: 401);
    });
    final github = MockClient((_) async => http.Response('', 500));
    final controller = GitHubController(
      GitHubApi(
        mediatorUrl: Uri.parse('https://mediator.example'),
        mediatorClient: mediator,
        githubClient: github,
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(mediator.close);
    addTearDown(github.close);

    await controller.restoreSession();

    expect(requests, 1);
    expect(controller.account, isNull);
    expect(controller.error, isNull);
  });

  test('keeps a verified account on discovery failure and refreshes the complete list', () async {
    var failDiscovery = true;
    final mediator = MockClient((request) async {
      if (request.url.path == '/oauth/github/token') return _json({'access_token': 'test-token'});
      return _json({'error': 'not found'}, status: 404);
    });
    final github = MockClient((request) async {
      if (request.url.path == '/user') return _json({'id': 17, 'login': 'canvas-user'});
      if (request.url.path == '/user/installations') {
        if (failDiscovery) return _json({'message': 'failed'}, status: 500);
        return _json({'total_count': 0, 'installations': <Object?>[]});
      }
      fail('Unexpected request ${request.url}');
    });
    final controller = GitHubController(
      GitHubApi(
        mediatorUrl: Uri.parse('https://mediator.example'),
        mediatorClient: mediator,
        githubClient: github,
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(mediator.close);
    addTearDown(github.close);

    await controller.restoreSession();
    expect(controller.account?.id, 17);
    expect(controller.discoveryError, isNotNull);
    expect(controller.discoveryLoading, isFalse);
    expect(controller.repositories, isEmpty);

    failDiscovery = false;
    await controller.refreshRepositories();
    expect(controller.account?.id, 17);
    expect(controller.discoveryError, isNull);
    expect(controller.installations, isEmpty);
  });

  test('preserves last complete discovery on refresh failure but clears on reconnect', () async {
    var discoveryMode = 'complete';
    final mediator = MockClient((request) async {
      if (request.url.path == '/oauth/github/token') return _json({'access_token': 'test-token'});
      return _json({'error': 'not found'}, status: 404);
    });
    final github = MockClient((request) async {
      if (request.url.path == '/user') {
        if (discoveryMode == 'reconnect') return _json({'message': 'expired'}, status: 401);
        return _json({'id': 17, 'login': 'canvas-user'});
      }
      if (request.url.path == '/user/installations') {
        final installationId = discoveryMode == 'partial' ? 66 : 55;
        return _json({
          'total_count': 1,
          'installations': [
            {
              'id': installationId,
              'account': {'id': 17, 'login': 'canvas-user'},
              'permissions': {'contents': 'write'},
              'html_url': 'https://github.com/settings/installations/$installationId',
            },
          ],
        });
      }
      if (request.url.path == '/user/installations/66/repositories') {
        return _json({'message': 'failed'}, status: 500);
      }
      if (request.url.path == '/user/installations/55/repositories') {
        return _json({
          'total_count': 1,
          'repositories': [
            {
              'id': 155,
              'name': 'canvas',
              'full_name': 'octo/canvas',
              'owner': {'login': 'octo'},
              'private': false,
              'default_branch': 'main',
              'permissions': {'pull': true, 'push': true},
              'archived': false,
              'disabled': false,
            },
          ],
        });
      }
      fail('Unexpected request ${request.url}');
    });
    final controller = GitHubController(
      GitHubApi(
        mediatorUrl: Uri.parse('https://mediator.example'),
        mediatorClient: mediator,
        githubClient: github,
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(mediator.close);
    addTearDown(github.close);

    await controller.restoreSession();
    expect(controller.account?.id, 17);
    expect(controller.installations.map((installation) => installation.id), [55]);
    expect(controller.repositories.map((repository) => repository.id), [155]);

    discoveryMode = 'partial';
    await controller.refreshRepositories();
    expect(controller.account?.id, 17);
    expect(controller.installations.map((installation) => installation.id), [55]);
    expect(controller.repositories.map((repository) => repository.id), [155]);
    expect(controller.discoveryError, 'GitHub is temporarily unavailable.');
    expect(controller.discoveryLoading, isFalse);

    discoveryMode = 'reconnect';
    await controller.refreshRepositories();
    expect(controller.account, isNull);
    expect(controller.installations, isEmpty);
    expect(controller.repositories, isEmpty);
    expect(controller.discoveryError, isNull);
    expect(controller.error, 'Reconnect GitHub to continue.');
  });

  test('ignores discovery completion after local logout', () async {
    final delayedInstallations = Completer<http.Response>();
    final mediator = MockClient((request) async {
      if (request.url.path == '/oauth/github/token') return _json({'access_token': 'test-token'});
      if (request.url.path == '/session/logout') return http.Response('', 204);
      return _json({'error': 'not found'}, status: 404);
    });
    final github = MockClient((request) async {
      if (request.url.path == '/user') return _json({'id': 17, 'login': 'canvas-user'});
      if (request.url.path == '/user/installations') return await delayedInstallations.future;
      fail('Unexpected request ${request.url}');
    });
    final controller = GitHubController(
      GitHubApi(
        mediatorUrl: Uri.parse('https://mediator.example'),
        mediatorClient: mediator,
        githubClient: github,
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(mediator.close);
    addTearDown(github.close);

    final restoration = controller.restoreSession();
    while (!controller.discoveryLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    await expectLater(controller.logout(), throwsA(isA<StateError>()));
    delayedInstallations.complete(_json({'total_count': 0, 'installations': <Object?>[]}));
    await restoration;

    expect(controller.account, isNull);
    expect(controller.installations, isEmpty);
    expect(controller.repositories, isEmpty);
    expect(controller.discoveryLoading, isFalse);
    expect(controller.logoutNeedsRetry, isTrue);
  });

  test('does not notify listeners when an operation completes after disposal', () async {
    final completion = Completer<void>();
    final mediator = MockClient((_) async => http.Response('', 500));
    final github = MockClient((_) async => http.Response('', 500));
    final controller = GitHubController(
      GitHubApi(
        mediatorUrl: Uri.parse('https://mediator.example'),
        mediatorClient: mediator,
        githubClient: github,
      ),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    final operation = controller.run(() => completion.future);
    expect(notifications, 1);
    controller.dispose();
    mediator.close();
    github.close();
    completion.complete();

    await operation;

    expect(notifications, 1);
    expect(controller.busy, isFalse);
  });
}

http.Response _json(Object value, {int status = 200, Map<String, String> headers = const {}}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json', ...headers},
);
