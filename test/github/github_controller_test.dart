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
        return _json({'access_token': 'not-for-storage', 'scope': 'repo'});
      }
      if (request.url.path == '/session/logout') {
        return failLogout ? _json({'error': 'private response'}, status: 500) : http.Response('', 204);
      }
      return _json({'error': 'not found'}, status: 404);
    });
    final github = MockClient((request) async {
      expect(request.url.path, '/user');
      return _json({'id': 17, 'login': 'canvas-user'}, headers: {'x-oauth-scopes': 'repo'});
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

    await controller.restoreSession(shouldCheck: true);
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

  test('run clears stale errors on success and disconnects on insufficient scope', () async {
    final mediator = MockClient((request) async {
      if (request.url.path == '/oauth/github/token') {
        return _json({'access_token': 'test-token', 'scope': 'repo'});
      }
      return _json({'error': 'not found'}, status: 404);
    });
    final github = MockClient(
      (_) async => _json({'id': 17, 'login': 'canvas-user'}, headers: {'x-oauth-scopes': 'repo'}),
    );
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

    await controller.restoreSession(shouldCheck: true);
    controller.error = 'stale error';
    await expectLater(controller.run(() async => 'complete'), completion('complete'));
    expect(controller.error, isNull);

    await expectLater(
      controller.run(() async {
        throw const GitHubApiException(
          'Reconnect GitHub and grant the repo scope.',
          kind: GitHubErrorKind.insufficientScope,
        );
      }),
      throwsA(isA<GitHubApiException>()),
    );
    expect(controller.account, isNull);
    expect(controller.error, 'Reconnect GitHub and grant the repo scope.');
    expect(controller.logoutNeedsRetry, isFalse);
    expect(controller.busy, isFalse);
  });

  test('does not contact the session service without a marker or destination', () async {
    var requests = 0;
    final mediator = MockClient((_) async {
      requests++;
      return http.Response('', 500);
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

    await controller.restoreSession(shouldCheck: false);

    expect(requests, 0);
    expect(controller.account, isNull);
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
