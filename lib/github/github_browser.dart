// Isolates browser-only GitHub navigation and cookie-enabled mediator setup.

import 'package:elseplane/github/github_api.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

GitHubApi createBrowserGitHubApi(Uri mediatorUrl) {
  final mediatorClient = BrowserClient()..withCredentials = true;
  return GitHubApi(mediatorUrl: mediatorUrl, mediatorClient: mediatorClient, githubClient: http.Client());
}

Uri gitHubAppInstallationUri(String slug) {
  if (slug.length > 100 || !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(slug)) {
    throw ArgumentError.value(slug, 'slug', 'Expected a valid GitHub App slug');
  }
  return Uri.https('github.com', '/apps/$slug/installations/new');
}

void navigateGitHubAuthorization(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host.toLowerCase() != 'github.com' ||
      uri.path != '/login/oauth/authorize' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    throw ArgumentError.value(uri, 'uri', 'Expected the GitHub OAuth authorization URL');
  }
  web.window.location.href = uri.toString();
}

bool consumeGitHubCompletion() {
  final current = Uri.parse(web.window.location.href);
  final parameters = <String, dynamic>{
    for (final entry in current.queryParametersAll.entries) entry.key: entry.value,
  };
  final completionValues = parameters['github'];
  if (completionValues is! List<String> || !completionValues.contains('complete')) return false;
  final remaining = completionValues.where((value) => value != 'complete').toList();
  if (remaining.isEmpty) {
    parameters.remove('github');
  } else {
    parameters['github'] = remaining;
  }
  web.window.history.replaceState(
    null,
    '',
    current.replace(queryParameters: parameters).toString(),
  );
  return true;
}

void openGitHubLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.toLowerCase() != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    throw ArgumentError.value(url, 'url', 'Expected an HTTPS GitHub URL');
  }
  web.window.open(uri.toString(), '_blank', 'noopener');
}
