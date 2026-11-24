// Owns GitHub and mediator HTTP boundaries for manual tree transfers.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:http/http.dart' as http;

const Duration _requestTimeout = Duration(seconds: 15);
const Duration _discoveryTimeout = Duration(seconds: 60);
const int _pageSize = 100;
const int _maximumJsonResponseBytes = 32 * 1024 * 1024;
const int _maximumGitHubBlobBytes = 100 * 1024 * 1024;
const _githubApiVersion = '2022-11-28';

enum GitHubErrorKind {
  reconnect,
  rateLimited,
  permissionDenied,
  missingResource,
  emptyRepository,
  invalidData,
  conflict,
  network,
  server,
}

class GitHubApiException implements Exception {
  const GitHubApiException(
    this.message, {
    required this.kind,
    this.statusCode,
    this.retryAfter,
  });

  final String message;
  final GitHubErrorKind kind;
  final int? statusCode;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

final class GitHubConflict extends GitHubApiException {
  const GitHubConflict(super.message, {this.path}) : super(kind: GitHubErrorKind.conflict);

  final String? path;
}

final class GitHubDefaultBranchChanged extends GitHubApiException {
  const GitHubDefaultBranchChanged()
    : super(
        'The repository default branch changed. Refresh and reselect the repository.',
        kind: GitHubErrorKind.invalidData,
      );
}

final class GitHubUnconfirmedCommit extends GitHubApiException {
  const GitHubUnconfirmedCommit({
    required this.sha,
    required this.url,
  }) : super('GitHub may have updated the branch.', kind: GitHubErrorKind.network);

  final String sha;
  final String url;
}

final class GitHubAccount {
  const GitHubAccount({required this.id, required this.login});

  final int id;
  final String login;
}

final class GitHubInstallation {
  const GitHubInstallation({
    required this.id,
    required this.accountId,
    required this.accountLogin,
    required this.managementUri,
    required this.contentsPermission,
  });

  final int id;
  final int accountId;
  final String accountLogin;
  final Uri managementUri;
  final String contentsPermission;

  bool get canReadContents => contentsPermission == 'read' || contentsPermission == 'write';
  bool get canWriteContents => contentsPermission == 'write';
}

final class GitHubRepository {
  const GitHubRepository({
    required this.installationId,
    required this.id,
    required this.owner,
    required this.name,
    required this.isPrivate,
    required this.defaultBranch,
    required this.canPull,
    required this.canPush,
    required this.archived,
    required this.disabled,
  });

  final int installationId;
  final int id;
  final String owner;
  final String name;
  final bool isPrivate;
  final String defaultBranch;
  final bool canPull;
  final bool canPush;
  final bool archived;
  final bool disabled;

  String get fullName => '$owner/$name';
}

final class GitHubTreeEntry {
  const GitHubTreeEntry({required this.path, required this.sha, required this.type, required this.mode, this.size});

  final String path;
  final String sha;
  final String type;
  final String mode;
  final int? size;

  bool get isRegularBlob => type == 'blob' && (mode == '100644' || mode == '100755');
  bool get isDirectory => type == 'tree' && mode == '040000';
}

final class GitHubSnapshot {
  GitHubSnapshot({required this.commitSha, required this.treeSha, required Map<String, GitHubTreeEntry> entries})
    : entries = Map.unmodifiable(entries);

  final String commitSha;
  final String treeSha;
  final Map<String, GitHubTreeEntry> entries;
}

final class GitHubCommitResult {
  const GitHubCommitResult({
    required this.commitSha,
    required this.url,
  });

  final String commitSha;
  final String url;
}

/// Returns whether [message] contains non-whitespace content.
bool isValidGitHubCommitMessage(String message) => message.trim().isNotEmpty;

/// GitHub operations with memory-only session state. Clients remain caller-owned.
final class GitHubApi {
  GitHubApi({required Uri mediatorUrl, required http.Client mediatorClient, required http.Client githubClient})
    : _mediatorUrl = _validateMediatorUrl(mediatorUrl) {
    _mediatorClient = mediatorClient;
    _githubClient = githubClient;
  }

  final Uri _mediatorUrl;
  late final http.Client _mediatorClient;
  late final http.Client _githubClient;

  Future<Uri> startAuthorization() async {
    final response = await _mediatorPost('/oauth/github/start');
    final object = _decodeObject(response.bodyBytes, 'Invalid authorization response');
    final rawUrl = object['authorization_url'];
    if (rawUrl is! String) _invalid('Invalid authorization response');
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.path != '/login/oauth/authorize' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      _invalid('Mediator returned an unsafe GitHub authorization URL');
    }
    return uri;
  }

  Future<GitHubAccount> account() async {
    final token = await _currentToken();
    final response = await _githubRequest('GET', _apiUri(['user']), token: token);
    final object = _decodeObject(response.bodyBytes, 'Invalid GitHub account response');
    final id = object['id'];
    final login = object['login'];
    if (id is! int || id <= 0 || login is! String || login.isEmpty) {
      _invalid('Invalid GitHub account response');
    }
    return GitHubAccount(id: id, login: login);
  }

  Future<({List<GitHubInstallation> installations, List<GitHubRepository> repositories})> discoverRepositories() async {
    final deadline = _DiscoveryDeadline();
    try {
      final token = await _currentToken(deadline: deadline);
      await _accountWithToken(token, deadline: deadline);
      final installations = await _discoverInstallations(token, deadline);
      final repositoriesById = <int, GitHubRepository>{};
      for (final installation in installations) {
        final repositories = await _discoverInstallationRepositories(installation.id, token, deadline);
        for (final repository in repositories) {
          final previous = repositoriesById[repository.id];
          if (previous != null && !_sameRepositoryDetails(previous, repository)) {
            _invalid('GitHub returned inconsistent repository details');
          }
          repositoriesById.putIfAbsent(repository.id, () => repository);
        }
      }
      deadline.check();
      final repositories = repositoriesById.values.toList()
        ..sort((left, right) {
          final folded = left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase());
          return folded != 0 ? folded : left.fullName.compareTo(right.fullName);
        });
      return (
        installations: List<GitHubInstallation>.unmodifiable(installations),
        repositories: List<GitHubRepository>.unmodifiable(repositories),
      );
    } on _DiscoveryDeadlineExceeded {
      throw const GitHubApiException(
        'Repository discovery took too long. Refresh to try again.',
        kind: GitHubErrorKind.network,
      );
    }
  }

  Future<GitHubDestination> resolveRepository(GitHubRepository repository) async {
    _validateRepositorySelection(repository);
    final token = await _currentToken();
    final account = await _accountWithToken(token);
    final current = await _findInstallationRepository(repository.installationId, repository.id, token);
    if (current == null) _membershipDenied();
    _verifyRepositorySelection(repository, current);
    _requirePullAccess(current);
    final destination = GitHubDestination(
      accountId: account.id,
      repositoryId: current.id,
      owner: current.owner,
      repository: current.name,
      branch: current.defaultBranch,
    );
    await _branchHead(destination, token);
    return destination;
  }

  Future<void> logout() async {
    final response = await _mediatorPost('/session/logout');
    if (response.statusCode != 204 && (response.statusCode < 200 || response.statusCode >= 300)) {
      _throwResponse(response, mediator: true);
    }
  }

  /// Captures one latest-default-branch tree and reads supported files lazily by
  /// their immutable blob SHAs.
  Future<TransferSource> readRepository(
    GitHubDestination destination, {
    required int installationId,
    bool Function()? isCurrent,
  }) async {
    final token = await _currentToken(isCurrent: isCurrent);
    await _verifyTransferDestination(destination, installationId, token, isCurrent: isCurrent);
    final snapshot = await _snapshot(destination, token, isCurrent: isCurrent);
    final entries = _transferEntries(snapshot);
    final byPath = {for (final entry in snapshot.entries.values) entry.path: entry};
    final reads = <String, Future<Uint8List>>{};
    return _GitHubTransferSource(
      entries,
      (path) {
        _checkImportCurrent(isCurrent);
        final entry = byPath[path];
        final isImage = _isTransferAttachmentPath(path);
        if (entry == null || !entry.isRegularBlob || (!isImage && !_isTransferDocumentPath(path))) {
          _invalid('Unsupported GitHub transfer read');
        }
        return reads.putIfAbsent(
          entry.sha.toLowerCase(),
          () => _readTransferBlob(destination, token, entry, isImage, isCurrent),
        );
      },
      () => _checkImportCurrent(isCurrent),
    );
  }

  /// Publishes a prepared transfer tree in one commit on a freshly captured
  /// default-branch head, reusing matching regular blobs from that tree.
  Future<GitHubCommitResult> commitTransfer(
    GitHubDestination destination,
    TransferTree tree, {
    required int installationId,
    required String message,
  }) async {
    if (!isValidGitHubCommitMessage(message)) {
      _invalid('A commit message is required.');
    }
    _validateTransferTree(tree);

    final token = await _currentToken();
    await _verifyTransferDestination(destination, installationId, token, forCommit: true);
    final current = await _snapshot(destination, token);
    _validateTransferOutput(current, tree);

    final existingBlobs = {
      for (final entry in current.entries.values)
        if (entry.isRegularBlob) entry.sha.toLowerCase(),
    };
    final changes = <Map<String, Object?>>[];
    for (final path in tree.files.keys.toList()..sort()) {
      final bytes = tree.files[path]!;
      final blobId = _gitBlobId(bytes);
      final sha = existingBlobs.contains(blobId) ? blobId : await _createBlob(destination, token, bytes);
      changes.add(_treeBlob(path, sha));
    }

    final treeResponse = await _githubRequest(
      'POST',
      _repoUri(destination, ['git', 'trees']),
      token: token,
      body: {'base_tree': current.treeSha, 'tree': changes},
    );
    final createdTree = _decodeObject(treeResponse.bodyBytes, 'Invalid GitHub tree response');
    final treeSha = _requiredSha(createdTree['sha'], 'Invalid GitHub tree response');
    final commitResponse = await _githubRequest(
      'POST',
      _repoUri(destination, ['git', 'commits']),
      token: token,
      body: {
        'message': message,
        'tree': treeSha,
        'parents': [current.commitSha],
      },
    );
    final commit = _decodeObject(commitResponse.bodyBytes, 'Invalid GitHub commit response');
    final commitSha = _requiredSha(commit['sha'], 'Invalid GitHub commit response');
    final htmlUrl = commit['html_url'];
    final commitUrl = htmlUrl is String ? htmlUrl : _commitUrl(destination, commitSha);

    late final http.Response refResponse;
    try {
      refResponse = await _githubRequest(
        'PATCH',
        _refUpdateUri(destination),
        token: token,
        body: {'sha': commitSha, 'force': false},
        checkResponse: false,
      );
    } on GitHubApiException catch (error) {
      if (error.kind == GitHubErrorKind.network ||
          error.kind == GitHubErrorKind.server ||
          error.kind == GitHubErrorKind.invalidData) {
        throw GitHubUnconfirmedCommit(sha: commitSha, url: commitUrl);
      }
      rethrow;
    }
    if (refResponse.statusCode < 200 || refResponse.statusCode >= 300) {
      if (refResponse.statusCode >= 500) {
        throw GitHubUnconfirmedCommit(sha: commitSha, url: commitUrl);
      }
      if (refResponse.statusCode == 409 || refResponse.statusCode == 422) {
        _conflict('The branch changed or rejected this commit. Choose the repository again before trying again.');
      }
      _throwResponse(refResponse);
    }
    return GitHubCommitResult(commitSha: commitSha, url: commitUrl);
  }

  Future<GitHubSnapshot> _snapshot(
    GitHubDestination destination,
    String token, {
    bool Function()? isCurrent,
  }) async {
    final commitSha = await _branchHead(destination, token, isCurrent: isCurrent);
    final commitResponse = await _githubRequest(
      'GET',
      _repoUri(destination, ['git', 'commits', commitSha]),
      token: token,
      isCurrent: isCurrent,
    );
    final commit = _decodeObject(commitResponse.bodyBytes, 'Invalid GitHub commit response');
    final treeObject = commit['tree'];
    if (treeObject is! Map) _invalid('GitHub commit has no tree');
    final treeSha = _requiredSha(treeObject['sha'], 'Invalid GitHub tree response');
    final treeResponse = await _githubRequest(
      'GET',
      _repoUri(destination, ['git', 'trees', treeSha]),
      token: token,
      query: {'recursive': '1'},
      isCurrent: isCurrent,
    );
    final tree = _decodeObject(treeResponse.bodyBytes, 'Invalid GitHub tree response');
    if (tree['truncated'] is! bool) _invalid('Invalid GitHub tree response');
    if (tree['truncated'] == true) _invalid('This repository is too large to browse because its Git tree is truncated');
    final rawEntries = tree['tree'];
    if (rawEntries is! List) _invalid('Invalid GitHub tree response');
    final entries = <String, GitHubTreeEntry>{};
    for (final raw in rawEntries) {
      if (raw is! Map) _invalid('Invalid GitHub tree entry');
      final path = raw['path'];
      final sha = raw['sha'];
      final type = raw['type'];
      final mode = raw['mode'];
      final size = raw['size'];
      if (path is! String ||
          path.isEmpty ||
          sha is! String ||
          !_isSha(sha) ||
          type is! String ||
          mode is! String ||
          (size != null && (size is! int || size < 0))) {
        _invalid('Invalid GitHub tree entry');
      }
      if (entries.containsKey(path)) _invalid('GitHub returned duplicate tree paths');
      entries[path] = GitHubTreeEntry(path: path, sha: sha, type: type, mode: mode, size: size as int?);
    }
    return GitHubSnapshot(commitSha: commitSha, treeSha: treeSha, entries: entries);
  }

  Future<Uint8List> _fetchBlob(
    GitHubDestination destination,
    String token,
    GitHubTreeEntry entry, {
    required int maximumBytes,
    bool Function()? isCurrent,
  }) async {
    if (!entry.isRegularBlob) _invalid('Unsupported Git object: ${entry.path}');
    final declaredSize = entry.size;
    if (declaredSize == null) _invalid('GitHub did not declare a size for ${entry.path}');
    if (declaredSize > maximumBytes) _invalid('File exceeds its size limit: ${entry.path}');
    final response = await _githubRequest(
      'GET',
      _repoUri(destination, ['git', 'blobs', entry.sha]),
      token: token,
      maximumResponseBytes: declaredSize,
      rawResponse: true,
      isCurrent: isCurrent,
    );
    final bytes = response.bodyBytes;
    if (bytes.length != declaredSize) _invalid('GitHub blob size does not match its tree entry');
    if (_gitBlobId(bytes) != entry.sha.toLowerCase()) _invalid('GitHub blob content does not match its Git ID');
    return bytes;
  }

  String _gitBlobId(Uint8List bytes) {
    late final Digest digest;
    sha1.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((values) {
          digest = values.single;
        }),
      )
      ..add(ascii.encode('blob ${bytes.length}\x00'))
      ..add(bytes)
      ..close();
    return digest.toString();
  }

  Future<String> _createBlob(GitHubDestination destination, String token, Uint8List bytes) async {
    if (bytes.length > _maximumGitHubBlobBytes) _invalid("File exceeds GitHub's 100 MiB blob limit");
    final response = await _githubRequest(
      'POST',
      _repoUri(destination, ['git', 'blobs']),
      token: token,
      body: {'content': base64.encode(bytes), 'encoding': 'base64'},
    );
    return _requiredSha(
      _decodeObject(response.bodyBytes, 'Invalid GitHub blob response')['sha'],
      'Invalid GitHub blob response',
    );
  }

  Future<List<GitHubInstallation>> _discoverInstallations(String token, _DiscoveryDeadline deadline) async {
    final result = <GitHubInstallation>[];
    final seen = <int, GitHubInstallation>{};
    var pageNumber = 1;
    var totalCount = -1;
    var received = 0;
    while (true) {
      deadline.check();
      final response = await _githubRequest(
        'GET',
        _apiUri(['user', 'installations']),
        token: token,
        query: {'per_page': '$_pageSize', 'page': '$pageNumber'},
        deadline: deadline,
      );
      final page = _decodePage(response, 'installations', 'Invalid GitHub installations response');
      if (totalCount < 0) {
        totalCount = page.totalCount;
      } else if (page.totalCount != totalCount) {
        _invalid('GitHub installation pagination changed during discovery');
      }
      received += page.items.length;
      for (final raw in page.items) {
        final installation = _parseInstallation(raw);
        final previous = seen[installation.id];
        if (previous != null && !_sameInstallation(previous, installation)) {
          _invalid('GitHub returned inconsistent installation details');
        }
        if (previous == null) {
          seen[installation.id] = installation;
          result.add(installation);
        }
      }
      final nextPage = _nextPage(response.headers['link'], ['user', 'installations'], pageNumber);
      _validatePageProgress(totalCount, received, nextPage);
      if (nextPage == null) break;
      pageNumber = nextPage;
    }
    result.sort((left, right) {
      final folded = left.accountLogin.toLowerCase().compareTo(right.accountLogin.toLowerCase());
      return folded != 0 ? folded : left.id.compareTo(right.id);
    });
    return result;
  }

  Future<List<GitHubRepository>> _discoverInstallationRepositories(
    int installationId,
    String token,
    _DiscoveryDeadline deadline,
  ) async {
    final result = <GitHubRepository>[];
    final seen = <int, GitHubRepository>{};
    var pageNumber = 1;
    var totalCount = -1;
    var received = 0;
    while (true) {
      deadline.check();
      final response = await _githubRequest(
        'GET',
        _installationRepositoriesUri(installationId),
        token: token,
        query: {'per_page': '$_pageSize', 'page': '$pageNumber'},
        deadline: deadline,
      );
      final page = _decodePage(response, 'repositories', 'Invalid GitHub repositories response');
      if (totalCount < 0) {
        totalCount = page.totalCount;
      } else if (page.totalCount != totalCount) {
        _invalid('GitHub repository pagination changed during discovery');
      }
      received += page.items.length;
      for (final raw in page.items) {
        final repository = _parseRepository(raw, installationId);
        final previous = seen[repository.id];
        if (previous != null && !_sameRepositoryDetails(previous, repository)) {
          _invalid('GitHub returned inconsistent repository details');
        }
        if (previous == null) {
          seen[repository.id] = repository;
          result.add(repository);
        }
      }
      final path = ['user', 'installations', '$installationId', 'repositories'];
      final nextPage = _nextPage(response.headers['link'], path, pageNumber);
      _validatePageProgress(totalCount, received, nextPage);
      if (nextPage == null) break;
      pageNumber = nextPage;
    }
    return result;
  }

  Future<GitHubRepository?> _findInstallationRepository(
    int installationId,
    int repositoryId,
    String token, {
    bool Function()? isCurrent,
  }) async {
    if (installationId <= 0 || repositoryId <= 0) _invalid('Invalid GitHub repository selection');
    var pageNumber = 1;
    var totalCount = -1;
    var received = 0;
    GitHubRepository? match;
    while (true) {
      final path = ['user', 'installations', '$installationId', 'repositories'];
      final response = await _githubRequest(
        'GET',
        _installationRepositoriesUri(installationId),
        token: token,
        query: {'per_page': '$_pageSize', 'page': '$pageNumber'},
        isCurrent: isCurrent,
      );
      final page = _decodePage(response, 'repositories', 'Invalid GitHub repositories response');
      if (totalCount < 0) {
        totalCount = page.totalCount;
      } else if (page.totalCount != totalCount) {
        _invalid('GitHub repository pagination changed during verification');
      }
      received += page.items.length;
      for (final raw in page.items) {
        final repository = _parseRepository(raw, installationId);
        if (repository.id == repositoryId) match = repository;
      }
      final nextPage = _nextPage(response.headers['link'], path, pageNumber);
      _validatePageProgress(totalCount, received, nextPage);
      if (match != null || nextPage == null) return match;
      pageNumber = nextPage;
    }
  }

  Uri _installationRepositoriesUri(int installationId) =>
      _apiUri(['user', 'installations', '$installationId', 'repositories']);

  _GitHubPage _decodePage(http.Response response, String key, String error) {
    final object = _decodeObject(response.bodyBytes, error);
    final totalCount = object['total_count'];
    final rawItems = object[key];
    if (totalCount is! int || totalCount < 0 || rawItems is! List || rawItems.length > _pageSize) {
      _invalid(error);
    }
    if (rawItems.any((item) => item is! Map || item.keys.any((key) => key is! String))) _invalid(error);
    return _GitHubPage(totalCount, List<Object?>.unmodifiable(rawItems));
  }

  GitHubInstallation _parseInstallation(Object? raw) {
    if (raw is! Map) _invalid('Invalid GitHub installation');
    final id = raw['id'];
    final account = raw['account'];
    final permissions = raw['permissions'];
    final accountId = account is Map ? account['id'] : null;
    final accountLogin = account is Map ? account['login'] : null;
    final contents = permissions is Map ? permissions['contents'] : null;
    final managementUrl = raw['html_url'];
    if (id is! int ||
        id <= 0 ||
        accountId is! int ||
        accountId <= 0 ||
        accountLogin is! String ||
        !_validRepositoryName(accountLogin) ||
        contents is! String ||
        (contents != 'read' && contents != 'write') ||
        managementUrl is! String) {
      _invalid('Invalid GitHub installation');
    }
    final uri = Uri.tryParse(managementUrl);
    if (uri == null || !_validInstallationManagementUri(uri, accountLogin, id)) {
      _invalid('GitHub returned an unsafe installation management URL');
    }
    return GitHubInstallation(
      id: id,
      accountId: accountId,
      accountLogin: accountLogin,
      managementUri: uri,
      contentsPermission: contents,
    );
  }

  GitHubRepository _parseRepository(Object? raw, int installationId) {
    if (raw is! Map) _invalid('Invalid GitHub repository');
    final id = raw['id'];
    final name = raw['name'];
    final fullName = raw['full_name'];
    final owner = raw['owner'];
    final ownerLogin = owner is Map ? owner['login'] : null;
    final isPrivate = raw['private'];
    final defaultBranch = raw['default_branch'];
    final permissions = raw['permissions'];
    final canPull = permissions is Map ? permissions['pull'] : null;
    final canPush = permissions is Map ? permissions['push'] : null;
    final archived = raw['archived'];
    final disabled = raw['disabled'];
    if (installationId <= 0 ||
        id is! int ||
        id <= 0 ||
        ownerLogin is! String ||
        !_validRepositoryName(ownerLogin) ||
        name is! String ||
        !_validRepositoryName(name) ||
        fullName != '$ownerLogin/$name' ||
        isPrivate is! bool ||
        defaultBranch is! String ||
        !_validBranch(defaultBranch) ||
        canPull is! bool ||
        canPush is! bool ||
        archived is! bool ||
        disabled is! bool) {
      _invalid('Invalid GitHub repository');
    }
    return GitHubRepository(
      installationId: installationId,
      id: id,
      owner: ownerLogin,
      name: name,
      isPrivate: isPrivate,
      defaultBranch: defaultBranch,
      canPull: canPull,
      canPush: canPush,
      archived: archived,
      disabled: disabled,
    );
  }

  bool _validInstallationManagementUri(Uri uri, String accountLogin, int id) {
    if (uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final segments = uri.pathSegments;
    final personal = segments.length == 3 && segments[0] == 'settings' && segments[1] == 'installations';
    final organization =
        segments.length == 5 &&
        segments[0] == 'organizations' &&
        segments[1].toLowerCase() == accountLogin.toLowerCase() &&
        segments[2] == 'settings' &&
        segments[3] == 'installations';
    return (personal || organization) && segments.last == '$id';
  }

  int? _nextPage(String? linkHeader, List<String> pathSegments, int pageNumber) {
    if (linkHeader == null || linkHeader.trim().isEmpty) return null;
    final links = _splitLinkHeader(linkHeader);
    int? nextPage;
    for (final value in links) {
      final match = RegExp(r'^\s*<([^<>]+)>\s*;(.*)$').firstMatch(value);
      if (match == null) _invalid('Invalid GitHub pagination metadata');
      final parameters = match.group(2)!.split(';');
      String? relation;
      for (final parameter in parameters) {
        final entry = RegExp(r'^\s*([A-Za-z][A-Za-z0-9_-]*)\s*=\s*(?:"([^"]*)"|([^\s]+))\s*$').firstMatch(parameter);
        if (entry == null) _invalid('Invalid GitHub pagination metadata');
        if (entry.group(1)!.toLowerCase() == 'rel') relation = entry.group(2) ?? entry.group(3);
      }
      if (relation == null || relation.isEmpty) _invalid('Invalid GitHub pagination metadata');
      if (relation.split(RegExp(r'\s+')).contains('next')) {
        if (nextPage != null) _invalid('Invalid GitHub pagination metadata');
        final uri = Uri.tryParse(match.group(1)!);
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host.toLowerCase() != 'api.github.com' ||
            uri.port != 443 ||
            uri.userInfo.isNotEmpty ||
            uri.path != _apiUri(pathSegments).path ||
            uri.hasFragment) {
          _invalid('Unsafe GitHub pagination metadata');
        }
        final query = uri.queryParametersAll;
        if (query.length != 2 ||
            query['per_page']?.length != 1 ||
            query['per_page']!.single != '$_pageSize' ||
            query['page']?.length != 1) {
          _invalid('Invalid GitHub pagination metadata');
        }
        final valuePage = int.tryParse(query['page']!.single);
        if (valuePage == null || valuePage != pageNumber + 1) _invalid('Invalid GitHub pagination metadata');
        nextPage = valuePage;
      }
    }
    return nextPage;
  }

  List<String> _splitLinkHeader(String header) {
    final result = <String>[];
    var start = 0;
    var inAngle = false;
    var inQuote = false;
    for (var index = 0; index < header.length; index++) {
      final char = header[index];
      if (char == '"' && (index == 0 || header[index - 1] != r'\')) inQuote = !inQuote;
      if (!inQuote) {
        if (char == '<') inAngle = true;
        if (char == '>') inAngle = false;
        if (char == ',' && !inAngle) {
          result.add(header.substring(start, index).trim());
          start = index + 1;
        }
      }
    }
    if (inAngle || inQuote) _invalid('Invalid GitHub pagination metadata');
    result.add(header.substring(start).trim());
    if (result.any((item) => item.isEmpty)) _invalid('Invalid GitHub pagination metadata');
    return result;
  }

  void _validatePageProgress(int totalCount, int received, int? nextPage) {
    if (received > totalCount ||
        (nextPage == null && received != totalCount) ||
        (nextPage != null && received >= totalCount)) {
      _invalid('GitHub returned incomplete pagination metadata');
    }
  }

  bool _sameInstallation(GitHubInstallation left, GitHubInstallation right) =>
      left.accountId == right.accountId &&
      left.accountLogin == right.accountLogin &&
      left.managementUri == right.managementUri &&
      left.contentsPermission == right.contentsPermission;

  bool _sameRepositoryDetails(GitHubRepository left, GitHubRepository right) =>
      left.owner == right.owner &&
      left.name == right.name &&
      left.isPrivate == right.isPrivate &&
      left.defaultBranch == right.defaultBranch &&
      left.canPull == right.canPull &&
      left.canPush == right.canPush &&
      left.archived == right.archived &&
      left.disabled == right.disabled;

  Future<String> _currentToken({
    _DiscoveryDeadline? deadline,
    bool Function()? isCurrent,
  }) async {
    final response = await _mediatorPost(
      '/oauth/github/token',
      deadline: deadline,
      isCurrent: isCurrent,
    );
    final object = _decodeObject(response.bodyBytes, 'Invalid session response');
    final value = object['access_token'];
    final tokenType = object['token_type'];
    final scope = object['scope'];
    final expiresIn = object['expires_in'];
    if (value is! String ||
        value.isEmpty ||
        (tokenType != null && (tokenType is! String || tokenType.toLowerCase() != 'bearer')) ||
        (scope != null && scope is! String) ||
        (expiresIn != null && (expiresIn is! int || expiresIn <= 0))) {
      _invalid('Invalid session response');
    }
    return value;
  }

  Future<GitHubAccount> _accountWithToken(
    String token, {
    _DiscoveryDeadline? deadline,
    bool Function()? isCurrent,
  }) async {
    final response = await _githubRequest(
      'GET',
      _apiUri(['user']),
      token: token,
      deadline: deadline,
      isCurrent: isCurrent,
    );
    final object = _decodeObject(response.bodyBytes, 'Invalid GitHub account response');
    final id = object['id'];
    final login = object['login'];
    if (id is! int || id <= 0 || login is! String || login.isEmpty) _invalid('Invalid GitHub account response');
    return GitHubAccount(id: id, login: login);
  }

  Future<void> _verifyTransferDestination(
    GitHubDestination destination,
    int installationId,
    String token, {
    bool forCommit = false,
    bool Function()? isCurrent,
  }) async {
    _validateDestination(destination);
    if (installationId <= 0) _invalid('Invalid GitHub repository selection');
    final account = await _accountWithToken(token, isCurrent: isCurrent);
    if (account.id != destination.accountId) {
      throw const GitHubApiException(
        'Reconnect the GitHub account used for this repository.',
        kind: GitHubErrorKind.reconnect,
      );
    }
    final repository = await _findInstallationRepository(
      installationId,
      destination.repositoryId,
      token,
      isCurrent: isCurrent,
    );
    if (repository == null) _membershipDenied();
    if (repository.owner != destination.owner || repository.name != destination.repository) {
      throw const GitHubApiException(
        'Repository identity changed. Choose the repository again before transferring.',
        kind: GitHubErrorKind.invalidData,
      );
    }
    if (repository.defaultBranch != destination.branch) {
      throw const GitHubDefaultBranchChanged();
    }
    _requirePullAccess(repository);
    if (forCommit && (!repository.canPush || repository.archived || repository.disabled)) {
      throw const GitHubApiException(
        'This repository does not allow commits. Check repository permissions and status.',
        kind: GitHubErrorKind.permissionDenied,
      );
    }
  }

  void _validateRepositorySelection(GitHubRepository repository) {
    if (repository.installationId <= 0 ||
        repository.id <= 0 ||
        !_validRepositoryName(repository.owner) ||
        !_validRepositoryName(repository.name) ||
        !_validBranch(repository.defaultBranch)) {
      _invalid('Invalid GitHub repository selection');
    }
  }

  void _verifyRepositorySelection(GitHubRepository selected, GitHubRepository current) {
    if (selected.id != current.id || selected.owner != current.owner || selected.name != current.name) {
      throw const GitHubApiException(
        'Repository identity changed. Refresh and choose the repository again.',
        kind: GitHubErrorKind.invalidData,
      );
    }
    if (selected.defaultBranch != current.defaultBranch) {
      throw const GitHubDefaultBranchChanged();
    }
  }

  void _requirePullAccess(GitHubRepository repository) {
    if (!repository.canPull) {
      throw const GitHubApiException(
        'You do not have permission to read this repository.',
        kind: GitHubErrorKind.permissionDenied,
      );
    }
  }

  Never _membershipDenied() => throw const GitHubApiException(
    'This repository is no longer available through the selected GitHub App installation.',
    kind: GitHubErrorKind.permissionDenied,
  );

  Future<String> _branchHead(
    GitHubDestination destination,
    String token, {
    bool Function()? isCurrent,
  }) async {
    final response = await _githubRequest(
      'GET',
      _refUri(destination),
      token: token,
      checkResponse: false,
      isCurrent: isCurrent,
    );
    _checkImportCurrent(isCurrent);
    if (response.statusCode == 404 || response.statusCode == 409) {
      final branches = await _githubRequest(
        'GET',
        _repoUri(destination, ['branches']),
        token: token,
        query: {'per_page': '1'},
        checkResponse: false,
        isCurrent: isCurrent,
      );
      _checkImportCurrent(isCurrent);
      if (branches.statusCode < 200 || branches.statusCode >= 300) _throwResponse(branches);
      final values = _decodeList(branches.bodyBytes, 'Invalid GitHub branches response');
      if (values.length > 1 || values.any((value) => value is! Map)) _invalid('Invalid GitHub branches response');
      if (values.isEmpty) {
        throw const GitHubApiException(
          'This repository is empty. Add a README on GitHub, then refresh.',
          kind: GitHubErrorKind.emptyRepository,
        );
      }
      final branch = values.single;
      if (branch is! Map) _invalid('Invalid GitHub branches response');
      final name = branch['name'];
      if (name is! String || !_validBranch(name)) _invalid('Invalid GitHub branches response');
      _conflict('The repository default branch is unavailable. Refresh and choose the repository again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) _throwResponse(response);
    final refObject = _decodeObject(response.bodyBytes, 'Invalid GitHub branch response');
    final object = refObject['object'];
    if (object is! Map || object['type'] != 'commit') _invalid('GitHub branch does not point to a commit');
    return _requiredSha(object['sha'], 'Invalid GitHub branch response');
  }

  List<TransferEntry> _transferEntries(GitHubSnapshot snapshot) {
    final result = <TransferEntry>[];
    final declaredSizesBySha = <String, int>{};
    var declaredTotal = 0;
    for (final entry in snapshot.entries.values) {
      if (!_isSafeRepoPath(entry.path)) _invalid('Invalid GitHub tree path');
      try {
        validateTransferPath(entry.path);
      } on FormatException {
        _invalid('Invalid GitHub tree path');
      }
      if (entry.isDirectory) {
        if (entry.size != null && entry.size != 0) _invalid('Invalid GitHub tree directory metadata');
        result.add(TransferEntry(path: entry.path, kind: TransferEntryKind.directory, size: entry.size));
        continue;
      }
      if (!entry.isRegularBlob) _invalid('Unsupported Git object: ${entry.path}');

      final size = entry.size;
      final isGitMetadata = entry.path.split('/').contains('.git');
      if (size == null && !isGitMetadata) _invalid('GitHub did not declare a size for ${entry.path}');
      if (size != null) {
        if (size > _maximumGitHubBlobBytes) _invalid("File exceeds GitHub's 100 MiB blob limit: ${entry.path}");
        if (_isRepositoryAttachmentPath(entry.path) && size > attachmentMaximumBytes) {
          _invalid('Attachment exceeds 10 MiB: ${entry.path}');
        }
        final sha = entry.sha.toLowerCase();
        final previousSize = declaredSizesBySha[sha];
        if (previousSize != null && previousSize != size) {
          _invalid('GitHub returned inconsistent sizes for the same blob');
        }
        declaredSizesBySha[sha] = size;
        if (size > canvasTransferMaximumBytes - declaredTotal) _invalid('Repository exceeds 140 MiB');
        declaredTotal += size;
      }
      result.add(TransferEntry(path: entry.path, kind: TransferEntryKind.regularFile, size: size));
    }

    try {
      validateTransferEntries(result);
    } on FormatException {
      _invalid('Invalid GitHub repository tree');
    }
    return List.unmodifiable(result);
  }

  Future<Uint8List> _readTransferBlob(
    GitHubDestination destination,
    String token,
    GitHubTreeEntry entry,
    bool isImage,
    bool Function()? isCurrent,
  ) async {
    _checkImportCurrent(isCurrent);
    final bytes = await _fetchBlob(
      destination,
      token,
      entry,
      maximumBytes: isImage ? attachmentMaximumBytes : _maximumGitHubBlobBytes,
      isCurrent: isCurrent,
    );
    return bytes.asUnmodifiableView();
  }

  void _validateTransferTree(TransferTree tree) {
    try {
      validateTransferEntries([
        for (final path in tree.files.keys) TransferEntry(path: path, kind: TransferEntryKind.regularFile),
        for (final path in tree.directories) TransferEntry(path: path, kind: TransferEntryKind.directory),
      ]);
    } on FormatException {
      _invalid('Invalid transfer tree');
    }

    if (tree.directories.any(
      (path) => path.split('/').any((segment) => segment == 'attachments' || segment == '.git'),
    )) {
      _invalid('Reserved transfer directory');
    }

    var total = 0;
    for (final entry in tree.files.entries) {
      final path = entry.key;
      final isDocument = _isTransferDocumentPath(path);
      final isImage = _isTransferAttachmentPath(path);
      if ((!isDocument && !isImage) || path.split('/').contains('.git')) {
        _invalid('Unsupported transfer output path: $path');
      }
      if (isImage && entry.value.length > attachmentMaximumBytes) {
        _invalid('Attachment exceeds 10 MiB: $path');
      }
      if (entry.value.length > _maximumGitHubBlobBytes) {
        _invalid("File exceeds GitHub's 100 MiB blob limit: $path");
      }
      if (entry.value.length > canvasTransferMaximumBytes - total) _invalid('Transfer exceeds 140 MiB');
      total += entry.value.length;
    }
  }

  void _validateTransferOutput(GitHubSnapshot snapshot, TransferTree tree) {
    final requiredDirectories = <String>{};
    for (final path in tree.files.keys) {
      var parent = _parentPath(path);
      while (parent.isNotEmpty) {
        requiredDirectories.add(parent);
        parent = _parentPath(parent);
      }
      if (_isTransferDocumentPath(path)) {
        final attachments = _joinPath(_parentPath(path), 'attachments');
        requiredDirectories.add(attachments);
        parent = _parentPath(attachments);
        while (parent.isNotEmpty) {
          requiredDirectories.add(parent);
          parent = _parentPath(parent);
        }
      }
    }

    for (final path in requiredDirectories.toList()..sort()) {
      final existing = snapshot.entries[path];
      if (existing != null && !existing.isDirectory) {
        _conflict('A repository file blocks a required directory', path);
      }
    }

    for (final path in tree.files.keys.toList()..sort()) {
      final existing = snapshot.entries[path];
      if (existing != null && !existing.isRegularBlob) {
        _conflict('A repository object occupies this output path', path);
      }
      for (final remote in snapshot.entries.values) {
        if (_isAncestorPath(path, remote.path)) {
          _conflict('The output path blocks existing repository content', remote.path);
        }
      }
    }
  }

  Future<http.Response> _mediatorPost(
    String path, {
    _DiscoveryDeadline? deadline,
    bool Function()? isCurrent,
  }) async {
    _checkImportCurrent(isCurrent);
    deadline?.check();
    final uri = _mediatorUrl.replace(path: path);
    late final http.Response response;
    try {
      final abort = deadline == null ? null : Completer<void>();
      final request =
          (abort == null ? http.Request('POST', uri) : http.AbortableRequest('POST', uri, abortTrigger: abort.future))
            ..headers.addAll(const {
              'Content-Type': 'application/json',
              'X-OAuth-Bridge': '1',
              'Accept': 'application/json',
            })
            ..body = '{}';
      response = await _sendBounded(_mediatorClient, request, 64 * 1024, deadline: deadline, abort: abort);
    } on _DiscoveryDeadlineExceeded {
      rethrow;
    } on _ResponseTooLarge {
      _invalid('GitHub session service response is too large');
    } on Object {
      throw const GitHubApiException('The GitHub session service could not be reached.', kind: GitHubErrorKind.network);
    }
    _checkImportCurrent(isCurrent);
    if (response.statusCode < 200 || response.statusCode >= 300) _throwResponse(response, mediator: true);
    return response;
  }

  Future<http.Response> _githubRequest(
    String method,
    Uri uri, {
    required String token,
    Object? body,
    Map<String, String>? query,
    bool checkResponse = true,
    int maximumResponseBytes = _maximumJsonResponseBytes,
    bool rawResponse = false,
    _DiscoveryDeadline? deadline,
    bool Function()? isCurrent,
  }) async {
    _checkImportCurrent(isCurrent);
    deadline?.check();
    final target = query == null ? uri : uri.replace(queryParameters: query);
    late final http.Response response;
    try {
      final abort = deadline == null ? null : Completer<void>();
      final request =
          (abort == null
                ? http.Request(method, target)
                : http.AbortableRequest(method, target, abortTrigger: abort.future))
            ..headers.addAll({
              'Accept': rawResponse ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
              'Authorization': 'Bearer $token',
              'X-GitHub-Api-Version': _githubApiVersion,
            });
      if (rawResponse) request.followRedirects = false;
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body);
      }
      response = await _sendBounded(
        _githubClient,
        request,
        maximumResponseBytes,
        rawResponse: rawResponse,
        deadline: deadline,
        abort: abort,
      );
    } on _DiscoveryDeadlineExceeded {
      rethrow;
    } on _ResponseTooLarge {
      _invalid('GitHub response is too large');
    } on Object {
      throw const GitHubApiException(
        'GitHub could not be reached. Check your connection and try again.',
        kind: GitHubErrorKind.network,
      );
    }
    _checkImportCurrent(isCurrent);
    if (checkResponse && (response.statusCode < 200 || response.statusCode >= 300)) _throwResponse(response);
    return response;
  }

  void _throwResponse(http.Response response, {bool mediator = false}) {
    final status = response.statusCode;
    final headers = response.headers;
    if (status == 401) {
      throw const GitHubApiException('Reconnect GitHub to continue.', kind: GitHubErrorKind.reconnect, statusCode: 401);
    }
    if (status == 429 ||
        (status == 403 && (headers['x-ratelimit-remaining'] == '0' || headers.containsKey('retry-after')))) {
      final parsedRetryAfter = _retryAfter(headers);
      final retryAfter = parsedRetryAfter ?? const Duration(minutes: 1);
      throw GitHubApiException(
        parsedRetryAfter == null
            ? 'GitHub rate limit reached. Try again in a minute.'
            : retryAfter == Duration.zero
            ? 'GitHub rate limit reached. Try again.'
            : 'GitHub rate limit reached. Try again in ${_ceilSeconds(retryAfter)} seconds.',
        kind: GitHubErrorKind.rateLimited,
        statusCode: status,
        retryAfter: retryAfter,
      );
    }
    if (status == 403) {
      throw GitHubApiException(
        'GitHub denied access. Check write permissions, organization restrictions, or branch protection.',
        kind: GitHubErrorKind.permissionDenied,
        statusCode: status,
      );
    }
    if (status == 404) {
      throw GitHubApiException(
        'The GitHub repository, branch, or file was not found.',
        kind: GitHubErrorKind.missingResource,
        statusCode: status,
      );
    }
    if (status == 409 || status == 422) {
      throw GitHubApiException(
        'GitHub rejected the repository update.',
        kind: GitHubErrorKind.conflict,
        statusCode: status,
      );
    }
    if (status >= 500) {
      throw GitHubApiException(
        mediator ? 'The GitHub session service is temporarily unavailable.' : 'GitHub is temporarily unavailable.',
        kind: GitHubErrorKind.server,
        statusCode: status,
      );
    }
    throw GitHubApiException(
      mediator ? 'The GitHub session request failed.' : 'GitHub rejected the request.',
      kind: GitHubErrorKind.invalidData,
      statusCode: status,
    );
  }

  Uri _apiUri(List<String> segments) => Uri(scheme: 'https', host: 'api.github.com', pathSegments: segments);

  Uri _repoUri(GitHubDestination destination, List<String> segments) =>
      _apiUri(['repos', destination.owner, destination.repository, ...segments]);

  Uri _refUri(GitHubDestination destination) =>
      _repoUri(destination, ['git', 'ref', 'heads', ...destination.branch.split('/')]);

  Uri _refUpdateUri(GitHubDestination destination) =>
      _repoUri(destination, ['git', 'refs', 'heads', ...destination.branch.split('/')]);

  String _commitUrl(GitHubDestination destination, String sha) =>
      'https://github.com/${Uri.encodeComponent(destination.owner)}/${Uri.encodeComponent(destination.repository)}/commit/$sha';

  Map<String, Object?> _treeBlob(String path, String sha, {String mode = '100644'}) => {
    'path': path,
    'mode': mode,
    'type': 'blob',
    'sha': sha,
  };

  Map<String, Object?> _decodeObject(Uint8List bytes, String error, {int maximumBytes = _maximumJsonResponseBytes}) {
    if (bytes.length > maximumBytes) _invalid('GitHub response is too large');
    try {
      final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (value is Map && value.keys.every((key) => key is String)) return value.cast<String, Object?>();
    } on Object {
      _invalid(error);
    }
    _invalid(error);
  }

  List<Object?> _decodeList(Uint8List bytes, String error, {int maximumBytes = _maximumJsonResponseBytes}) {
    if (bytes.length > maximumBytes) _invalid('GitHub response is too large');
    try {
      final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (value is List) return List<Object?>.unmodifiable(value);
    } on Object {
      _invalid(error);
    }
    _invalid(error);
  }

  Duration? _retryAfter(Map<String, String> headers) {
    final seconds = int.tryParse((headers['retry-after'] ?? '').trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    final reset = int.tryParse((headers['x-ratelimit-reset'] ?? '').trim());
    if (reset == null) return null;
    final delay = DateTime.fromMillisecondsSinceEpoch(reset * 1000).difference(DateTime.now());
    return delay.isNegative ? Duration.zero : delay;
  }

  int _ceilSeconds(Duration duration) =>
      (duration.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/ Duration.microsecondsPerSecond;

  Future<http.Response> _sendBounded(
    http.Client client,
    http.BaseRequest request,
    int maximumBytes, {
    bool rawResponse = false,
    _DiscoveryDeadline? deadline,
    Completer<void>? abort,
  }) async {
    try {
      final streamed = await _withRequestTimeout(client.send(request), deadline);
      if (rawResponse && (streamed.statusCode < 200 || streamed.statusCode >= 300)) {
        _cancelUnread(streamed.stream);
        return http.Response.bytes(
          Uint8List(0),
          streamed.statusCode,
          request: request,
          headers: streamed.headers,
          reasonPhrase: streamed.reasonPhrase,
        );
      }
      final responseBytes = await _withRequestTimeout(_readBounded(streamed.stream, maximumBytes), deadline);
      return http.Response.bytes(
        responseBytes,
        streamed.statusCode,
        request: request,
        headers: streamed.headers,
        reasonPhrase: streamed.reasonPhrase,
      );
    } on _DiscoveryDeadlineExceeded {
      if (abort != null && !abort.isCompleted) abort.complete();
      rethrow;
    } on TimeoutException {
      if (abort != null && !abort.isCompleted) abort.complete();
      rethrow;
    }
  }

  void _cancelUnread(Stream<List<int>> stream) {
    try {
      final subscription = stream.listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      );
      unawaited(subscription.cancel().catchError((Object error) {}));
    } on Object {
      // Cancellation is best-effort; status and headers remain authoritative.
    }
  }

  Future<T> _withRequestTimeout<T>(Future<T> future, _DiscoveryDeadline? deadline) {
    if (deadline == null) return future.timeout(_requestTimeout);
    deadline.check();
    final remaining = deadline.remaining;
    final timeout = remaining < _requestTimeout ? remaining : _requestTimeout;
    return future.timeout(
      timeout,
      onTimeout: () {
        if (deadline.expired) throw const _DiscoveryDeadlineExceeded();
        throw TimeoutException('GitHub request timed out');
      },
    );
  }

  Future<Uint8List> _readBounded(Stream<List<int>> stream, int maximumBytes) async {
    final output = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (chunk.length > maximumBytes - output.length) throw const _ResponseTooLarge();
      output.add(chunk);
    }
    return output.takeBytes();
  }

  String _parentPath(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

  String _joinPath(String parent, String relative) => parent.isEmpty ? relative : '$parent/$relative';

  bool _isAncestorPath(String ancestor, String child) => child.startsWith('$ancestor/');

  bool _isRepositoryAttachmentPath(String path) {
    final segments = path.split('/');
    return segments.length >= 2 && attachmentPathPattern.hasMatch(segments.skip(segments.length - 2).join('/'));
  }

  bool _isTransferAttachmentPath(String path) {
    final segments = path.split('/');
    return _isRepositoryAttachmentPath(path) &&
        !segments.take(segments.length - 2).any((segment) => segment == 'attachments' || segment == '.git');
  }

  bool _isTransferDocumentPath(String path) {
    final segments = path.split('/');
    return path.endsWith('.canvas.json') &&
        !segments.take(segments.length - 1).any((segment) => segment == 'attachments' || segment == '.git');
  }

  bool _isSafeRepoPath(String path) =>
      path.isNotEmpty &&
      !path.startsWith('/') &&
      !path.contains(r'\') &&
      path
          .split('/')
          .every(
            (segment) =>
                segment.isNotEmpty &&
                segment != '.' &&
                segment != '..' &&
                !segment.contains(RegExp(r'[\x00-\x1f\x7f-\x9f]')),
          );

  bool _validRepositoryName(String name) => RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name) && name != '.' && name != '..';

  bool _validBranch(String branch) =>
      branch.isNotEmpty &&
      !branch.startsWith('/') &&
      !branch.endsWith('/') &&
      !branch.contains('@{') &&
      branch
          .split('/')
          .every(
            (segment) =>
                segment.isNotEmpty &&
                segment != '.' &&
                segment != '..' &&
                !segment.endsWith('.lock') &&
                !segment.contains(RegExp(r'[\x00-\x20\x7f~^:?*\\\[]')),
          );

  void _validateDestination(GitHubDestination destination) {
    if (destination.accountId <= 0 ||
        destination.repositoryId <= 0 ||
        !_validRepositoryName(destination.owner) ||
        !_validRepositoryName(destination.repository) ||
        !_validBranch(destination.branch)) {
      _invalid('Invalid GitHub repository destination');
    }
  }

  String _requiredSha(Object? value, String error) {
    if (value is! String || !_isSha(value)) _invalid(error);
    return value;
  }

  bool _isSha(String value) => RegExp(r'^[0-9a-f]{40}$', caseSensitive: false).hasMatch(value);

  void _checkImportCurrent(bool Function()? isCurrent) {
    if (isCurrent != null && !isCurrent()) throw const _GitHubImportCancelled();
  }

  Never _invalid(String message) => throw GitHubApiException(message, kind: GitHubErrorKind.invalidData);

  Never _conflict(String message, [String? path]) => throw GitHubConflict(message, path: path);

  static Uri _validateMediatorUrl(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(
        uri,
        'mediatorUrl',
        'Must be an HTTPS service URL without credentials or query parameters',
      );
    }
    return uri;
  }
}

final class _ResponseTooLarge implements Exception {
  const _ResponseTooLarge();
}

final class _DiscoveryDeadlineExceeded implements Exception {
  const _DiscoveryDeadlineExceeded();
}

final class _GitHubImportCancelled implements Exception {
  const _GitHubImportCancelled();
}

final class _DiscoveryDeadline {
  _DiscoveryDeadline() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  Duration get remaining => _discoveryTimeout - _watch.elapsed;
  bool get expired => remaining.inMicroseconds <= 0;

  void check() {
    if (expired) throw const _DiscoveryDeadlineExceeded();
  }
}

final class _GitHubPage {
  const _GitHubPage(this.totalCount, this.items);

  final int totalCount;
  final List<Object?> items;
}

final class _GitHubTransferSource implements TransferSource {
  _GitHubTransferSource(List<TransferEntry> entries, this._read, this._check) : _entries = List.unmodifiable(entries);

  final List<TransferEntry> _entries;
  final Future<Uint8List> Function(String path) _read;
  final void Function() _check;

  @override
  Future<List<TransferEntry>> entries() async {
    _check();
    return _entries;
  }

  @override
  Future<Uint8List> read(String path) async => await _read(path);
}
