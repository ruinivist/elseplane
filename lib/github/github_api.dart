// Owns GitHub and mediator HTTP boundaries for manual single-canvas transfers.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:elseplane/library/transfer/canvas_remote_transfer.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const Duration _requestTimeout = Duration(seconds: 15);
const int _maximumJsonResponseBytes = 32 * 1024 * 1024;
const int _maximumGitHubBlobBytes = 100 * 1024 * 1024;
const _githubApiVersion = '2022-11-28';

enum GitHubErrorKind {
  reconnect,
  insufficientScope,
  rateLimited,
  permissionDenied,
  missingResource,
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

final class GitHubUnconfirmedCommit extends GitHubApiException {
  const GitHubUnconfirmedCommit({
    required this.commitSha,
    required this.url,
    required this.tracking,
  }) : super(
         'GitHub may have updated the branch. Check remote status before writing again.',
         kind: GitHubErrorKind.network,
       );

  final String commitSha;
  final String url;
  final GitHubCanvasTracking tracking;
}

final class GitHubAccount {
  const GitHubAccount({required this.id, required this.login});

  final int id;
  final String login;
}

final class GitHubTreeEntry {
  const GitHubTreeEntry({required this.path, required this.sha, required this.type, required this.mode, this.size});

  final String path;
  final String sha;
  final String type;
  final String mode;
  final int? size;

  bool get isRegularBlob => type == 'blob' && (mode == '100644' || mode == '100755');
}

final class GitHubSnapshot {
  GitHubSnapshot({required this.commitSha, required this.treeSha, required Map<String, GitHubTreeEntry> entries})
    : entries = Map.unmodifiable(entries);

  final String commitSha;
  final String treeSha;
  final Map<String, GitHubTreeEntry> entries;

  List<String> get canvasPaths => [
    for (final entry in entries.values)
      if (entry.isRegularBlob && entry.path.endsWith('.canvas')) entry.path,
  ]..sort();
}

final class GitHubCommitResult {
  const GitHubCommitResult({
    required this.noChanges,
    required this.commitSha,
    required this.url,
    required this.tracking,
  });

  final bool noChanges;
  final String? commitSha;
  final String url;
  final GitHubCanvasTracking tracking;
}

/// Returns whether [message] is a short lowercase Conventional Commit subject.
bool isValidGitHubCommitMessage(String message) {
  if (message.isEmpty || message != message.toLowerCase() || message.trim() != message || message.contains('\n')) {
    return false;
  }
  if (message.runes.length > 72) return false;
  return RegExp(r'^[a-z][a-z0-9-]*(?:\([a-z0-9][a-z0-9._/-]*\))?!?: [a-z0-9][^\r\n]*$').hasMatch(message);
}

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
  bool? _lastRepositoryPrivate;
  DateTime? _retryAt;

  bool? get lastRepositoryPrivate => _lastRepositoryPrivate;

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
    final response = await _githubRequest('GET', _apiUri(['user']), token: token.value);
    final object = _decodeObject(response.bodyBytes, 'Invalid GitHub account response');
    final id = object['id'];
    final login = object['login'];
    if (id is! int || id <= 0 || login is! String || login.isEmpty) {
      _invalid('Invalid GitHub account response');
    }
    _requireRepoScope(token.scope, response.headers['x-oauth-scopes']);
    return GitHubAccount(id: id, login: login);
  }

  Future<void> logout() async {
    final response = await _mediatorPost('/session/logout');
    if (response.statusCode != 204 && (response.statusCode < 200 || response.statusCode >= 300)) {
      _throwResponse(response, mediator: true);
    }
  }

  Future<GitHubDestination> repository(String ownerRepository) async {
    _lastRepositoryPrivate = null;
    final parts = ownerRepository.split('/');
    if (parts.length != 2 || !_validRepositoryName(parts[0]) || !_validRepositoryName(parts[1])) {
      _invalid('Enter a repository as owner/repository');
    }
    final token = await _currentToken();
    final account = await _accountWithToken(token);
    final response = await _githubRequest(
      'GET',
      _apiUri(['repos', parts[0], parts[1]]),
      token: token.value,
    );
    final object = _decodeObject(response.bodyBytes, 'Invalid GitHub repository response');
    final owner = object['owner'];
    final ownerLogin = owner is Map ? owner['login'] : null;
    final id = object['id'];
    final name = object['name'];
    final branch = object['default_branch'];
    final isPrivate = object['private'];
    if (id is! int ||
        id <= 0 ||
        ownerLogin is! String ||
        name is! String ||
        branch is! String ||
        branch.isEmpty ||
        isPrivate is! bool ||
        ownerLogin.toLowerCase() != parts[0].toLowerCase() ||
        name.toLowerCase() != parts[1].toLowerCase()) {
      _invalid('GitHub returned a different or invalid repository');
    }
    if (!_validBranch(branch)) _invalid('GitHub returned an invalid default branch');
    _lastRepositoryPrivate = isPrivate;
    return GitHubDestination(
      accountId: account.id,
      repositoryId: id,
      owner: ownerLogin,
      repository: name,
      branch: branch,
    );
  }

  Future<GitHubSnapshot> snapshot(GitHubDestination destination) async {
    final token = await _currentToken();
    await _verifyDestinationAccount(destination, token);
    return await _snapshot(destination, token.value);
  }

  Future<GitHubCanvasTracking?> checkPendingWrite(
    GitHubDestination destination, {
    required GitHubCanvasTracking pendingTracking,
    GitHubCanvasTracking? tracking,
  }) async {
    final current = await snapshot(destination);
    if (tracking != null) _validateTracking(tracking);
    _validateTracking(pendingTracking);

    final moved = tracking != null && tracking.path != pendingTracking.path;
    if (_matchesTracking(current, pendingTracking) && (!moved || !current.entries.containsKey(tracking.path))) {
      return pendingTracking;
    }
    if (tracking != null &&
        _matchesTracking(current, tracking) &&
        (!moved || !current.entries.containsKey(pendingTracking.path))) {
      _checkDestinationCollisions(current, pendingTracking.path, tracking);
      return tracking;
    }
    if (tracking == null && !current.entries.containsKey(pendingTracking.path)) {
      _checkDestinationCollisions(current, pendingTracking.path, null);
      return null;
    }
    _conflict(
      'The remote branch matches neither the confirmed canvas nor the pending write. Open the remote copy before writing again.',
      pendingTracking.path,
    );
  }

  Future<CanvasProject> openCanvas(GitHubDestination destination, GitHubSnapshot snapshot, String path) async {
    final token = await _currentToken();
    await _verifyDestinationAccount(destination, token);
    _validateCanvasPath(path);
    final documentEntry = snapshot.entries[path];
    if (documentEntry == null || !documentEntry.isRegularBlob) {
      _invalid('The selected canvas is not a regular GitHub file');
    }
    if ((documentEntry.size ?? 0) > canvasProjectMaximumBytes) {
      _invalid('Canvas exceeds 140 MiB');
    }
    final documentBytes = await _fetchBlob(
      destination,
      token.value,
      documentEntry,
      maximumBytes: canvasProjectMaximumBytes,
    );
    late final CanvasDocument document;
    try {
      document = CanvasDocument.fromJson(jsonDecode(utf8.decode(documentBytes, allowMalformed: false)));
    } on Object {
      _invalid('Invalid canvas document');
    }
    final paths = canvasAttachmentPaths(document);
    var totalBytes = documentBytes.length;
    final attachments = <String, Uint8List>{};
    final parent = _parentPath(path);
    for (final localPath in paths.toList()..sort()) {
      if (!attachmentPathPattern.hasMatch(localPath)) _invalid('Invalid canvas attachment path');
      final remotePath = _joinPath(parent, localPath);
      final entry = snapshot.entries[remotePath];
      if (entry == null || !entry.isRegularBlob) _invalid('Canvas attachment is missing or unsupported: $remotePath');
      if ((entry.size ?? 0) > attachmentMaximumBytes) _invalid('Canvas attachment exceeds 10 MiB: $remotePath');
      final bytes = await _fetchBlob(destination, token.value, entry, maximumBytes: attachmentMaximumBytes);
      totalBytes += bytes.length;
      if (totalBytes > canvasProjectMaximumBytes) _invalid('Canvas exceeds 140 MiB');
      attachments[localPath] = bytes;
    }
    try {
      return await decodeCanvasRemoteTransfer(documentBytes, attachments);
    } on Object {
      _invalid('Invalid canvas document or attachments');
    }
  }

  GitHubCanvasTracking trackingForCanvas(GitHubSnapshot snapshot, String path, CanvasProject project) {
    _validateCanvasPath(path);
    final document = snapshot.entries[path];
    if (document == null || !document.isRegularBlob) _invalid('Canvas is not a regular GitHub file');
    final localPaths = canvasAttachmentPaths(project.document);
    if (localPaths.length != project.attachments.length || !localPaths.containsAll(project.attachments.keys)) {
      _invalid('Canvas attachments do not match the document');
    }
    final parent = _parentPath(path);
    final attachmentShas = <String, String>{};
    final attachmentNames = <String, String>{};
    for (final localPath in localPaths) {
      if (!attachmentPathPattern.hasMatch(localPath)) _invalid('Invalid local attachment path');
      final remotePath = _joinPath(parent, localPath);
      final entry = snapshot.entries[remotePath];
      if (entry == null || !entry.isRegularBlob) _invalid('Canvas attachment is missing or unsupported');
      attachmentShas[remotePath] = entry.sha;
      attachmentNames[localPath] = localPath;
    }
    return GitHubCanvasTracking(
      path: path,
      documentSha: document.sha,
      attachmentShas: attachmentShas,
      attachmentNames: attachmentNames,
    );
  }

  Future<GitHubCommitResult> commitCanvas({
    required GitHubDestination destination,
    required String path,
    required CanvasProject project,
    required String message,
    required Future<void> Function(String commitSha, GitHubCanvasTracking tracking) beforeRefUpdate,
    GitHubCanvasTracking? tracking,
  }) async {
    _validateCanvasPath(path);
    if (!isValidGitHubCommitMessage(message)) {
      _invalid('Enter a lowercase Conventional Commit subject of 72 characters or fewer');
    }
    _validateProject(project);
    final token = await _currentToken();
    await _verifyDestinationAccount(destination, token);
    final current = await _snapshot(destination, token.value);
    _checkTracking(current, tracking);
    _checkDestinationCollisions(current, path, tracking);

    final parent = _parentPath(path);
    final oldNames = tracking?.attachmentNames ?? const <String, String>{};
    final remappings = <String, String>{};
    final nextAttachmentShas = <String, String>{};
    final nextAttachmentNames = <String, String>{};
    final changes = <Map<String, Object?>>[];
    final plannedAttachments = <String, String>{};
    final attachmentBytesByPath = <String, Uint8List>{};
    final existingAttachmentEntries = <String, GitHubTreeEntry>{};

    for (final localPath in project.attachments.keys.toList()..sort()) {
      var relativePath = oldNames[localPath] ?? localPath;
      if (!attachmentPathPattern.hasMatch(relativePath)) _invalid('Invalid tracked attachment mapping');
      var remotePath = _joinPath(parent, relativePath);
      var entry = current.entries[remotePath];
      final bytes = project.attachments[localPath]!;
      _checkFilePathCollisions(current, remotePath, allowExistingFile: entry != null);
      if (entry != null) {
        if (!entry.isRegularBlob) _invalid('Attachment destination is not a regular file: $remotePath');
        final oldBytes = await _fetchBlob(destination, token.value, entry, maximumBytes: attachmentMaximumBytes);
        if (!_sameBytes(bytes, oldBytes)) {
          relativePath = _unusedAttachmentName(relativePath, parent, current, nextAttachmentNames.values.toSet());
          remotePath = _joinPath(parent, relativePath);
          _checkFilePathCollisions(current, remotePath, allowExistingFile: false);
          entry = null;
        }
      }
      final previousLocalPath = plannedAttachments[remotePath];
      if (previousLocalPath != null) {
        if (_sameBytes(bytes, project.attachments[previousLocalPath]!)) {
          remappings[localPath] = relativePath;
          nextAttachmentNames[localPath] = relativePath;
          continue;
        }
        relativePath = _unusedAttachmentName(relativePath, parent, current, nextAttachmentNames.values.toSet());
        remotePath = _joinPath(parent, relativePath);
        _checkFilePathCollisions(current, remotePath, allowExistingFile: false);
        entry = null;
      }
      plannedAttachments[remotePath] = localPath;
      attachmentBytesByPath[remotePath] = bytes;
      if (entry != null) existingAttachmentEntries[remotePath] = entry;
      remappings[localPath] = relativePath;
      nextAttachmentNames[localPath] = relativePath;
    }

    final outgoingDocument = rebaseCanvasDocumentAttachments(project.document, remappings);
    final documentBytes = encodeRemoteCanvasDocument(outgoingDocument);
    final attachmentBytes = project.attachments.values.fold<int>(0, (total, bytes) => total + bytes.length);
    if (documentBytes.length > _maximumGitHubBlobBytes) {
      _invalid("Canvas document exceeds GitHub's 100 MiB blob limit");
    }
    if (documentBytes.length > canvasProjectMaximumBytes - attachmentBytes) _invalid('Canvas exceeds 140 MiB');

    for (final remotePath in attachmentBytesByPath.keys.toList()..sort()) {
      final existing = existingAttachmentEntries[remotePath];
      if (existing != null) {
        nextAttachmentShas[remotePath] = existing.sha;
      } else {
        final sha = await _createBlob(destination, token.value, attachmentBytesByPath[remotePath]!);
        changes.add(_treeBlob(remotePath, sha));
        nextAttachmentShas[remotePath] = sha;
      }
    }

    final documentEntry = current.entries[path];
    var documentSha = '';
    if (documentEntry != null) {
      if (!documentEntry.isRegularBlob) _conflict('Canvas path is occupied by an unsupported Git object', path);
      final oldBytes = await _fetchBlob(destination, token.value, documentEntry, maximumBytes: _maximumGitHubBlobBytes);
      if (_sameBytes(documentBytes, oldBytes)) {
        documentSha = documentEntry.sha;
      } else {
        documentSha = await _createBlob(destination, token.value, documentBytes);
        changes.add(_treeBlob(path, documentSha, mode: documentEntry.mode));
      }
    } else {
      documentSha = await _createBlob(destination, token.value, documentBytes);
      changes.add(_treeBlob(path, documentSha));
    }

    if (tracking != null && tracking.path != path) {
      changes.add({'path': tracking.path, 'mode': current.entries[tracking.path]!.mode, 'type': 'blob', 'sha': null});
    }
    final nextTracking = GitHubCanvasTracking(
      path: path,
      documentSha: documentSha,
      attachmentShas: nextAttachmentShas,
      attachmentNames: nextAttachmentNames,
    );
    final branchUrl = _branchUrl(destination);
    if (changes.isEmpty) {
      return GitHubCommitResult(noChanges: true, commitSha: null, url: branchUrl, tracking: nextTracking);
    }

    final treeResponse = await _githubRequest(
      'POST',
      _repoUri(destination, ['git', 'trees']),
      token: token.value,
      body: {'base_tree': current.treeSha, 'tree': changes},
    );
    final tree = _decodeObject(treeResponse.bodyBytes, 'Invalid GitHub tree response');
    final treeSha = _requiredSha(tree['sha'], 'Invalid GitHub tree response');
    final commitResponse = await _githubRequest(
      'POST',
      _repoUri(destination, ['git', 'commits']),
      token: token.value,
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

    await beforeRefUpdate(commitSha, nextTracking);
    late final http.Response refResponse;
    try {
      refResponse = await _githubRequest(
        'PATCH',
        _refUpdateUri(destination),
        token: token.value,
        body: {'sha': commitSha, 'force': false},
        checkResponse: false,
      );
    } on GitHubApiException catch (error) {
      if (error.kind == GitHubErrorKind.network ||
          error.kind == GitHubErrorKind.server ||
          error.kind == GitHubErrorKind.invalidData) {
        throw GitHubUnconfirmedCommit(commitSha: commitSha, url: branchUrl, tracking: nextTracking);
      }
      rethrow;
    }
    if (refResponse.statusCode < 200 || refResponse.statusCode >= 300) {
      if (refResponse.statusCode >= 500) {
        throw GitHubUnconfirmedCommit(commitSha: commitSha, url: branchUrl, tracking: nextTracking);
      }
      if (refResponse.statusCode == 409 || refResponse.statusCode == 422) {
        _conflict('The branch changed or rejected this commit. Reopen the remote canvas before trying again.', path);
      }
      _throwResponse(refResponse);
    }
    return GitHubCommitResult(noChanges: false, commitSha: commitSha, url: commitUrl, tracking: nextTracking);
  }

  Future<GitHubSnapshot> _snapshot(GitHubDestination destination, String token) async {
    final ref = await _githubRequest('GET', _refUri(destination), token: token);
    final refObject = _decodeObject(ref.bodyBytes, 'Invalid GitHub branch response');
    final object = refObject['object'];
    if (object is! Map || object['type'] != 'commit') _invalid('GitHub branch does not point to a commit');
    final commitSha = _requiredSha(object['sha'], 'Invalid GitHub branch response');
    final commitResponse = await _githubRequest(
      'GET',
      _repoUri(destination, ['git', 'commits', commitSha]),
      token: token,
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
  }) async {
    if (!entry.isRegularBlob) _invalid('Unsupported Git object: ${entry.path}');
    final declaredSize = entry.size;
    if (declaredSize == null) _invalid('GitHub did not declare a size for ${entry.path}');
    if (declaredSize > maximumBytes) _invalid('File exceeds its size limit: ${entry.path}');
    final maximumResponseBytes = _maximumBase64JsonBytes(maximumBytes);
    final response = await _githubRequest(
      'GET',
      _repoUri(destination, ['git', 'blobs', entry.sha]),
      token: token,
      maximumResponseBytes: maximumResponseBytes,
    );
    final blob = _decodeObject(
      response.bodyBytes,
      'Invalid GitHub blob response',
      maximumBytes: maximumResponseBytes,
    );
    final blobSize = blob['size'];
    final content = blob['content'];
    if (blob['sha'] != entry.sha ||
        blob['encoding'] != 'base64' ||
        content is! String ||
        blobSize is! int ||
        blobSize < 0 ||
        blobSize > maximumBytes) {
      _invalid('Invalid GitHub blob response');
    }
    final bytes = _decodeBase64(content);
    if (bytes.length != blobSize || bytes.length != declaredSize) {
      _invalid('GitHub blob size does not match its tree entry');
    }
    return bytes;
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

  Future<({String value, String? scope})> _currentToken() async {
    final response = await _mediatorPost('/oauth/github/token');
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
    final currentScope = scope is String ? scope : null;
    _requireRepoScope(currentScope, null);
    return (value: value, scope: currentScope);
  }

  Future<GitHubAccount> _accountWithToken(({String value, String? scope}) token) async {
    final response = await _githubRequest('GET', _apiUri(['user']), token: token.value);
    final object = _decodeObject(response.bodyBytes, 'Invalid GitHub account response');
    final id = object['id'];
    final login = object['login'];
    if (id is! int || id <= 0 || login is! String || login.isEmpty) _invalid('Invalid GitHub account response');
    _requireRepoScope(token.scope, response.headers['x-oauth-scopes']);
    return GitHubAccount(id: id, login: login);
  }

  Future<void> _verifyDestinationAccount(GitHubDestination destination, ({String value, String? scope}) token) async {
    _validateDestination(destination);
    final account = await _accountWithToken(token);
    if (account.id != destination.accountId) {
      throw const GitHubApiException(
        'Reconnect the GitHub account used for this repository.',
        kind: GitHubErrorKind.reconnect,
      );
    }
    final response = await _githubRequest(
      'GET',
      _apiUri(['repos', destination.owner, destination.repository]),
      token: token.value,
    );
    final repositoryId = _decodeObject(response.bodyBytes, 'Invalid GitHub repository response')['id'];
    if (repositoryId is! int || repositoryId <= 0) _invalid('Invalid GitHub repository response');
    if (repositoryId != destination.repositoryId) {
      throw const GitHubApiException(
        'Repository identity changed. Choose the repository again before transferring.',
        kind: GitHubErrorKind.invalidData,
      );
    }
  }

  Future<http.Response> _mediatorPost(String path) async {
    _checkRateLimit();
    final uri = _mediatorUrl.replace(path: path);
    late final http.Response response;
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(const {
          'Content-Type': 'application/json',
          'X-OAuth-Bridge': '1',
          'Accept': 'application/json',
        })
        ..body = '{}';
      response = await _sendBounded(_mediatorClient, request, 64 * 1024);
    } on _ResponseTooLarge {
      _invalid('GitHub session service response is too large');
    } on Object {
      throw const GitHubApiException('The GitHub session service could not be reached.', kind: GitHubErrorKind.network);
    }
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
  }) async {
    _checkRateLimit();
    final target = query == null ? uri : uri.replace(queryParameters: query);
    late final http.Response response;
    try {
      final request = http.Request(method, target)
        ..headers.addAll({
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': _githubApiVersion,
        });
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body);
      }
      response = await _sendBounded(_githubClient, request, maximumResponseBytes);
    } on _ResponseTooLarge {
      _invalid('GitHub response is too large');
    } on Object {
      throw const GitHubApiException(
        'GitHub could not be reached. Check your connection and try again.',
        kind: GitHubErrorKind.network,
      );
    }
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
      final retryAfter = _retryAfter(headers) ?? const Duration(seconds: 60);
      _retryAt = DateTime.now().add(retryAfter);
      throw GitHubApiException(
        'GitHub rate limit reached. Wait before trying again.',
        kind: GitHubErrorKind.rateLimited,
        statusCode: status,
        retryAfter: retryAfter,
      );
    }
    if (status == 403) {
      final accepted = headers['x-accepted-oauth-scopes'] ?? '';
      final actual = headers['x-oauth-scopes'] ?? '';
      if (_hasRepoScope(accepted) && !_hasRepoScope(actual)) {
        throw GitHubApiException(
          'Reconnect GitHub and grant the repo scope.',
          kind: GitHubErrorKind.insufficientScope,
          statusCode: status,
        );
      }
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

  String _branchUrl(GitHubDestination destination) =>
      'https://github.com/${Uri.encodeComponent(destination.owner)}/${Uri.encodeComponent(destination.repository)}/tree/${destination.branch.split('/').map(Uri.encodeComponent).join('/')}';

  String _commitUrl(GitHubDestination destination, String sha) =>
      'https://github.com/${Uri.encodeComponent(destination.owner)}/${Uri.encodeComponent(destination.repository)}/commit/$sha';

  Map<String, Object?> _treeBlob(String path, String sha, {String mode = '100644'}) => {
    'path': path,
    'mode': mode,
    'type': 'blob',
    'sha': sha,
  };

  void _checkTracking(GitHubSnapshot snapshot, GitHubCanvasTracking? tracking) {
    if (tracking == null) return;
    _validateCanvasPath(tracking.path);
    final document = snapshot.entries[tracking.path];
    if (document == null || !document.isRegularBlob || document.sha != tracking.documentSha) {
      _conflict('The linked canvas changed remotely. Reopen it before committing.', tracking.path);
    }
    for (final entry in tracking.attachmentShas.entries) {
      if (!_isSafeRepoPath(entry.key)) _invalid('Invalid tracked attachment path');
      final remote = snapshot.entries[entry.key];
      if (remote == null || !remote.isRegularBlob || remote.sha != entry.value) {
        _conflict('A linked attachment changed remotely. Reopen the canvas before committing.', entry.key);
      }
    }
    for (final entry in tracking.attachmentNames.entries) {
      if (!attachmentPathPattern.hasMatch(entry.key) || !attachmentPathPattern.hasMatch(entry.value)) {
        _invalid('Invalid tracked attachment mapping');
      }
    }
  }

  void _validateTracking(GitHubCanvasTracking tracking) {
    _validateCanvasPath(tracking.path);
    if (!_isSha(tracking.documentSha)) _invalid('Invalid tracked document SHA');
    final mappedPaths = <String>{};
    for (final entry in tracking.attachmentNames.entries) {
      if (!attachmentPathPattern.hasMatch(entry.key) || !attachmentPathPattern.hasMatch(entry.value)) {
        _invalid('Invalid tracked attachment mapping');
      }
      mappedPaths.add(_joinPath(_parentPath(tracking.path), entry.value));
    }
    for (final entry in tracking.attachmentShas.entries) {
      if (!_isSafeRepoPath(entry.key) || !_isSha(entry.value)) _invalid('Invalid tracked attachment SHA');
    }
    if (mappedPaths.length != tracking.attachmentShas.length ||
        !mappedPaths.containsAll(tracking.attachmentShas.keys)) {
      _invalid('Tracked attachment mappings do not match their blobs');
    }
  }

  bool _matchesTracking(GitHubSnapshot snapshot, GitHubCanvasTracking tracking) {
    final document = snapshot.entries[tracking.path];
    if (document == null || !document.isRegularBlob || document.sha != tracking.documentSha) return false;
    return tracking.attachmentShas.entries.every((entry) {
      final remote = snapshot.entries[entry.key];
      return remote != null && remote.isRegularBlob && remote.sha == entry.value;
    });
  }

  void _checkDestinationCollisions(GitHubSnapshot snapshot, String path, GitHubCanvasTracking? tracking) {
    final isUpdatingInPlace = tracking != null && tracking.path == path;
    if (!isUpdatingInPlace && snapshot.entries.containsKey(path)) {
      _conflict('The canvas destination is already occupied', path);
    }
    for (final entry in snapshot.entries.values) {
      if (entry.path == path && isUpdatingInPlace) continue;
      if (_isAncestorPath(entry.path, path) && entry.type != 'tree') {
        _conflict('A repository file blocks the canvas destination', entry.path);
      }
      if (_isAncestorPath(path, entry.path)) {
        _conflict('The canvas destination blocks existing repository content', entry.path);
      }
    }
    final attachmentsDir = _joinPath(_parentPath(path), 'attachments');
    final attachmentDirEntry = snapshot.entries[attachmentsDir];
    if (attachmentDirEntry != null && attachmentDirEntry.type != 'tree' && attachmentDirEntry.path != path) {
      _conflict('A repository file occupies the reserved attachments directory', attachmentsDir);
    }
  }

  void _checkFilePathCollisions(GitHubSnapshot snapshot, String path, {required bool allowExistingFile}) {
    for (final entry in snapshot.entries.values) {
      if (entry.path == path) {
        if (!allowExistingFile || entry.type != 'blob') _conflict('A repository object occupies this file path', path);
      } else if ((_isAncestorPath(entry.path, path) && entry.type != 'tree') || _isAncestorPath(path, entry.path)) {
        _conflict('A repository file or directory blocks this path', entry.path);
      }
    }
  }

  void _validateProject(CanvasProject project) {
    final referenced = canvasAttachmentPaths(project.document);
    if (referenced.length != project.attachments.length || !referenced.containsAll(project.attachments.keys)) {
      _invalid('Canvas attachments do not match the document');
    }
    var total = 0;
    for (final entry in project.attachments.entries) {
      if (!attachmentPathPattern.hasMatch(entry.key)) _invalid('Invalid local attachment path');
      if (entry.value.length > attachmentMaximumBytes) _invalid('Canvas attachment exceeds 10 MiB: ${entry.key}');
      total += entry.value.length;
    }
    if (total > canvasProjectMaximumBytes) _invalid('Canvas exceeds 140 MiB');
  }

  void _requireRepoScope(String? tokenScope, String? githubScope) {
    for (final scope in [tokenScope, githubScope]) {
      if (scope != null && !_hasRepoScope(scope)) {
        throw const GitHubApiException(
          'Reconnect GitHub and grant the repo scope.',
          kind: GitHubErrorKind.insufficientScope,
        );
      }
    }
  }

  bool _hasRepoScope(String value) => value.split(RegExp(r'[,\s]+')).any((scope) => scope == 'repo');

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

  Uint8List _decodeBase64(String source) {
    final compact = source.replaceAll('\r\n', '').replaceAll('\n', '');
    if (source.contains('\r') && source.replaceAll('\r\n', '').contains('\r') ||
        compact.contains(RegExp('[^A-Za-z0-9+/=]')) ||
        compact.length % 4 != 0) {
      _invalid('Invalid base64 GitHub blob');
    }
    try {
      final bytes = Uint8List.fromList(base64.decode(compact));
      if (base64.encode(bytes) != compact) _invalid('Invalid base64 GitHub blob');
      return bytes;
    } on Object {
      _invalid('Invalid base64 GitHub blob');
    }
  }

  Duration? _retryAfter(Map<String, String> headers) {
    final seconds = int.tryParse(headers['retry-after'] ?? '');
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    final reset = int.tryParse(headers['x-ratelimit-reset'] ?? '');
    if (reset == null) return null;
    final delay = DateTime.fromMillisecondsSinceEpoch(reset * 1000).difference(DateTime.now());
    return delay.isNegative ? Duration.zero : delay;
  }

  void _checkRateLimit() {
    final retryAt = _retryAt;
    if (retryAt == null) return;
    final now = DateTime.now();
    if (!retryAt.isAfter(now)) {
      _retryAt = null;
      return;
    }
    throw GitHubApiException(
      'GitHub rate limit reached. Wait before trying again.',
      kind: GitHubErrorKind.rateLimited,
      retryAfter: retryAt.difference(now),
    );
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  int _maximumBase64JsonBytes(int maximumBytes) {
    final encodedBytes = ((maximumBytes + 2) ~/ 3) * 4;
    final wrappedLines = encodedBytes ~/ 60;
    // Four bytes cover a JSON-escaped CRLF at each wrap.
    return encodedBytes + wrappedLines * 4 + 256 * 1024;
  }

  Future<http.Response> _sendBounded(http.Client client, http.BaseRequest request, int maximumBytes) async {
    final streamed = await client.send(request).timeout(_requestTimeout);
    final responseBytes = await _readBounded(streamed.stream, maximumBytes).timeout(_requestTimeout);
    return http.Response.bytes(
      responseBytes,
      streamed.statusCode,
      request: request,
      headers: streamed.headers,
      reasonPhrase: streamed.reasonPhrase,
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

  String _freshAttachmentName(String oldPath, Set<String> reserved) {
    final extension = oldPath.substring(oldPath.lastIndexOf('.') + 1);
    String path;
    do {
      path = 'attachments/${const Uuid().v4()}.$extension';
    } while (reserved.contains(path));
    return path;
  }

  String _unusedAttachmentName(String oldPath, String parent, GitHubSnapshot snapshot, Set<String> reserved) {
    String candidate;
    do {
      candidate = _freshAttachmentName(oldPath, reserved);
    } while (snapshot.entries.containsKey(_joinPath(parent, candidate)) || reserved.contains(candidate));
    return candidate;
  }

  String _parentPath(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

  String _joinPath(String parent, String relative) => parent.isEmpty ? relative : '$parent/$relative';

  bool _isAncestorPath(String ancestor, String child) => child.startsWith('$ancestor/');

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

  void _validateCanvasPath(String path) {
    if (!_isSafeRepoPath(path) || !path.endsWith('.canvas')) _invalid('Canvas path is invalid');
    if (path.split('/').take(path.split('/').length - 1).any((segment) => segment == 'attachments')) {
      _invalid('Canvas paths cannot be inside the reserved attachments directory');
    }
  }

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
