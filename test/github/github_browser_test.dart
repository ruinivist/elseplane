import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:elseplane/github/github_browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  late String originalUrl;

  setUp(() {
    originalUrl = web.window.location.href;
  });

  tearDown(() {
    web.window.history.replaceState(null, '', originalUrl);
  });

  group('consumeGitHubCompletion', () {
    test('removes completion values and preserves the rest of the URL', () {
      _setUrl(
        '/github-browser/canvas?keep=first&github=pending&github=complete&keep=second&github=linked&github=complete#canvas',
      );

      expect(consumeGitHubCompletion(), isTrue);

      final result = Uri.parse(web.window.location.href);
      expect(result.path, '/github-browser/canvas');
      expect(result.queryParametersAll, {
        'keep': ['first', 'second'],
        'github': ['pending', 'linked'],
      });
      expect(result.fragment, 'canvas');
    });

    test('leaves the URL unchanged when completion is absent', () {
      _setUrl('/github-browser/canvas?keep=value&github=pending#canvas');
      final before = web.window.location.href;

      expect(consumeGitHubCompletion(), isFalse);
      expect(web.window.location.href, before);
    });
  });

  test('rejects unsafe authorization URLs without navigating', () {
    _setUrl('/github-browser/authorization-check');
    final before = web.window.location.href;
    final invalidUrls = [
      'http://github.com/login/oauth/authorize',
      'https://github.example/login/oauth/authorize',
      'https://github.com/not-the-authorize-path',
      'https://user@github.com/login/oauth/authorize',
      'https://github.com:444/login/oauth/authorize',
    ];

    for (final value in invalidUrls) {
      expect(
        () => navigateGitHubAuthorization(Uri.parse(value)),
        throwsArgumentError,
        reason: value,
      );
      expect(web.window.location.href, before, reason: value);
    }
  });

  test('GitHub App installation URL validates the configured slug', () {
    expect(
      gitHubAppInstallationUri('elseplane-app'),
      Uri.parse('https://github.com/apps/elseplane-app/installations/new'),
    );
    for (final slug in ['', 'Elseplane', '../elseplane', 'app/name', 'app?x=1', '-app', 'app-']) {
      expect(() => gitHubAppInstallationUri(slug), throwsArgumentError, reason: slug);
    }
  });

  test('rejects unsafe GitHub links without opening a window', () {
    final originalOpen = web.window.getProperty<JSAny?>('open'.toJS);
    var openCalls = 0;
    web.window.setProperty(
      'open'.toJS,
      ((JSAny? _, JSAny? _, JSAny? _) {
        openCalls++;
        return null;
      }).toJS,
    );

    try {
      final invalidUrls = [
        'http://github.com/owner/repo',
        'javascript:alert(1)',
        'https://github.com.evil.example/owner/repo',
        'https://user@github.com/owner/repo',
        'https://github.com:444/owner/repo',
      ];

      for (final value in invalidUrls) {
        expect(() => openGitHubLink(value), throwsArgumentError, reason: value);
      }

      expect(openCalls, 0);
    } finally {
      web.window.setProperty('open'.toJS, originalOpen);
    }
  });

  test('opens the validated app installation URL in a separate tab', () {
    final originalOpen = web.window.getProperty<JSAny?>('open'.toJS);
    final openedUrls = <String>[];
    final targets = <String>[];
    final features = <String>[];
    web.window.setProperty(
      'open'.toJS,
      ((JSAny? url, JSAny? target, JSAny? feature) {
        openedUrls.add((url! as JSString).toDart);
        targets.add((target! as JSString).toDart);
        features.add((feature! as JSString).toDart);
        return null;
      }).toJS,
    );

    try {
      final uri = gitHubAppInstallationUri('elseplane-app');
      openGitHubLink(uri.toString());
      expect(openedUrls, ['https://github.com/apps/elseplane-app/installations/new']);
      expect(targets, ['_blank']);
      expect(features, ['noopener']);
    } finally {
      web.window.setProperty('open'.toJS, originalOpen);
    }
  });
}

void _setUrl(String pathAndQuery) {
  web.window.history.replaceState(null, '', pathAndQuery);
}
