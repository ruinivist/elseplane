// Owns the GitHub workflows for one Workspace lifetime.
// Connects the session and transfers to Sync settings and the canvas title.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/github/github_browser.dart';
import 'package:elseplane/github/github_commit_dialog.dart';
import 'package:elseplane/github/github_controller.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:flutter/material.dart';

// ---------- Workspace workflow ----------

class GitHubSync extends ChangeNotifier {
  GitHubSync({
    required GitHubApi api,
    required this.library,
    required this.attachmentStore,
    required this.beginTransfer,
    required this.endTransfer,
    required this.onImport,
    required String appSlug,
    this.navigate = navigateGitHubAuthorization,
    this.consumeCompletion = consumeGitHubCompletion,
    this.openLink = openGitHubLink,
  }) : session = GitHubController(api),
       installUri = gitHubAppInstallationUri(appSlug) {
    session.addListener(_sessionChanged);
  }

  final GitHubController session;
  final LibraryController library;
  final AttachmentStore attachmentStore;
  final bool Function() beginTransfer;
  final VoidCallback endTransfer;
  final Future<void> Function(
    TransferSource source, {
    required GitHubDestination githubDestination,
    required Future<bool> Function(Set<String>) confirmOverwrite,
    required ValueChanged<String> report,
  })
  onImport;
  final Uri installUri;
  final void Function(Uri) navigate;
  final bool Function() consumeCompletion;
  final void Function(String) openLink;

  // ---------- State ----------

  var _disposed = false;
  var _refreshRequired = false;
  String? _progress;
  String? message;
  Completer<bool>? _overwriteDecision;
  Set<String>? overwritePaths;
  var _attachmentRevision = 0;
  ({
    GitHubBaseline? baseline,
    CanvasDocument document,
    String path,
    String fileId,
    GitHubDestination destination,
    int attachmentRevision,
  })?
  _comparison;
  var _uncommitted = false;
  var _checkingAttachments = false;
  bool get uncommitted => _uncommitted;
  String? get progress => _progress;
  bool get busy => _progress != null || session.busy;
  GitHubDestination? get destination {
    final saved = library.library.githubDestination;
    return saved != null && saved.accountId == session.account?.id ? saved : null;
  }

  GitHubRepository? get repository {
    final saved = destination;
    return saved == null
        ? null
        : session.repositories
              .where(
                (repo) => repo.id == saved.repositoryId && repo.owner == saved.owner && repo.name == saved.repository,
              )
              .firstOrNull;
  }

  GitHubInstallation? _installation(GitHubRepository repo) =>
      session.installations.where((installation) => installation.id == repo.installationId).firstOrNull;

  bool get canSelect => !_refreshRequired && session.discoveryError == null && !session.discoveryLoading;

  GitHubRepository? get _readableRepository {
    final repo = repository;
    return canSelect &&
            repo != null &&
            repo.defaultBranch == destination?.branch &&
            repo.canPull &&
            _installation(repo)?.canReadContents == true
        ? repo
        : null;
  }

  bool get canImport => _readableRepository != null;

  bool get canCommit {
    final repo = _readableRepository;
    return repo != null && _installation(repo)!.canWriteContents && repo.canPush && !repo.archived && !repo.disabled;
  }

  bool get canCommitCurrent => uncommitted && !_checkingAttachments && canCommit;

  String? get repositoryStatus {
    if (_refreshRequired || session.discoveryLoading || session.discoveryError != null) return null;
    final saved = destination;
    if (saved == null) {
      return session.repositories.isEmpty ? 'No repositories are available. Manage GitHub access to continue.' : null;
    }
    final repo = repository;
    if (repo == null) return 'Saved repository is unavailable. Choose another repository or manage GitHub access.';
    if (repo.defaultBranch != saved.branch) {
      return 'Default branch changed from ${saved.branch} to ${repo.defaultBranch}. Reselect the repository to confirm.';
    }
    if (!canImport) return 'This repository requires Contents read access. Manage GitHub access to continue.';
    if (!canCommit) return 'This repository is read-only. You can import canvases.';
    return null;
  }

  // ---------- Session and setup ----------

  bool restore() {
    var completed = false;
    try {
      completed = consumeCompletion();
    } on Object catch (error) {
      _report(_errorMessage(error));
    }
    unawaited(session.restoreSession());
    return completed;
  }

  Future<void> connect() => _run('Connecting to GitHub…', () async {
    try {
      await library.flush();
    } on Object {
      _report('Could not save canvas. GitHub authorization was not started.');
      return;
    }
    if (_disposed) return;
    final authorization = await session.run(session.api.startAuthorization);
    if (!_disposed) navigate(authorization);
  });

  Future<void> selectRepository(int id) => _run('Checking repository…', () async {
    await library.flush();
    if (_disposed || !canSelect) return;
    final account = session.account;
    final repo = session.repositories.where((repo) => repo.id == id).firstOrNull;
    if (account == null || repo == null) {
      _report('Repository access could not be verified. Refresh and reselect the repository.');
      return;
    }
    if (!repo.canPull || _installation(repo)?.canReadContents != true) {
      _report('This repository requires Contents read access. Manage GitHub access to continue.');
      return;
    }
    final selected = await session.run(() => session.api.resolveRepository(repo));
    if (_disposed) return;
    if (session.account?.id != account.id || selected.accountId != account.id) {
      _report('GitHub account changed. Reconnect to select a repository.');
      return;
    }
    try {
      await library.setGitHubDestination(selected);
    } on Object {
      _report('Could not save the repository selection. Select it again to retry.');
    }
  });

  Future<void> manageAccess(Uri uri) => _run('Saving canvas…', () async {
    await library.flush();
    if (!_disposed) openLink(uri.toString());
  });

  Future<void> refreshRepositories() => _run('Refreshing repositories…', () async {
    await session.refreshRepositories();
    if (session.discoveryError == null) _refreshRequired = false;
  });

  Future<void> logout() => _run('Logging out…', session.logout);

  Future<void> skipImport() => _run('Saving GitHub settings…', _dismissImportPrompt);

  Future<void> _dismissImportPrompt() async {
    try {
      await library.dismissGitHubImportPrompt();
    } on Object {
      throw StateError('Could not save GitHub settings. Try again.');
    }
  }

  // ---------- Transfers ----------

  Future<void> importRepository(bool Function() reviewIsVisible) => _run('Preparing import…', () async {
    await library.flush();
    final repo = _readableRepository;
    final saved = destination;
    if (_disposed || !reviewIsVisible() || repo == null || saved == null) return;
    if (library.library.githubImportPromptPending) await _dismissImportPrompt();
    final source = await session.run(() => session.api.readRepository(saved, installationId: repo.installationId));
    if (_disposed || !reviewIsVisible()) return;
    await onImport(
      source,
      githubDestination: saved,
      confirmOverwrite: (paths) => _reviewOverwrite(paths, reviewIsVisible),
      report: _report,
    );
  });

  Future<bool> _reviewOverwrite(Set<String> paths, bool Function() reviewIsVisible) async {
    if (_disposed || !reviewIsVisible()) return false;
    final decision = _overwriteDecision = Completer<bool>();
    overwritePaths = paths;
    notifyListeners();
    return await decision.future;
  }

  void finishOverwriteReview({required bool overwrite}) {
    final decision = _overwriteDecision;
    if (decision == null) return;
    _overwriteDecision = null;
    overwritePaths = null;
    if (overwrite) _progress = 'Importing canvases…';
    decision.complete(overwrite);
    if (overwrite && !_disposed) notifyListeners();
  }

  Future<void> commit(BuildContext context) async {
    if (!canCommitCurrent) return;
    await _run(
      'Committing canvas…',
      () async {
        await library.flush();
        if (_disposed || !context.mounted || !canCommit) return;
        final repo = _readableRepository!;
        final saved = destination!;
        final captured = library.snapshot;
        final path = captured.serializedPath(captured.currentId);
        final message = await showGitHubCommitDialog(
          context,
          repository: repo.fullName,
          branch: saved.branch,
          newPath: path,
        );
        if (_disposed || message == null) return;
        final tree = await encodeTransfer(captured, attachmentStore, TransferScope.currentCanvas);
        if (_disposed) return;
        final baseline = GitHubBaseline.capture(saved, path, captured.current.document!, tree.files);
        final result = await session.run(
          () => session.api.commitTransfer(saved, tree, installationId: repo.installationId, message: message),
        );
        if (_disposed) return;
        var feedback = 'Canvas committed to GitHub.';
        try {
          await library.saveGitHubBaseline(captured.currentId, baseline);
        } on Object {
          feedback = 'Canvas committed to GitHub. Could not save its local sync baseline.';
        }
        if (context.mounted) _canvasFeedback(context, feedback, url: result.url, action: 'View commit');
      },
      onError: (error) {
        if (error is GitHubUnconfirmedCommit) {
          _canvasFeedback(
            context,
            'The branch update may have succeeded. Submitting again may create a duplicate commit.',
            url: error.url,
            action: 'Check GitHub',
          );
        } else {
          _canvasFeedback(context, _errorMessage(error));
        }
      },
    );
  }

  // ---------- Feedback ----------

  void _canvasFeedback(BuildContext context, String text, {String? url, String? action}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: url == null ? const Duration(seconds: 4) : const Duration(seconds: 10),
        action: url == null ? null : SnackBarAction(label: action!, onPressed: () => openLink(url)),
      ),
    );
  }

  Future<void> _run(String progress, Future<void> Function() operation, {void Function(Object)? onError}) async {
    if (_disposed || busy || !beginTransfer()) return;
    _progress = progress;
    message = null;
    notifyListeners();
    try {
      await operation();
    } on Object catch (error) {
      if (_disposed) return;
      if (error is GitHubDefaultBranchChanged) _refreshRequired = true;
      if (onError == null || error is GitHubDefaultBranchChanged) _report(_errorMessage(error));
      onError?.call(error);
    } finally {
      _progress = null;
      if (!_disposed) {
        endTransfer();
        notifyListeners();
      }
    }
  }

  void _report(String text) {
    if (_disposed) return;
    message = text;
    notifyListeners();
  }

  String _errorMessage(Object error) => switch (error) {
    GitHubApiException(:final message) => message,
    FormatException(:final message) => message,
    StateError(:final message) => message,
    _ => 'GitHub could not complete this action. Check your connection and try again.',
  };

  // ---------- Canvas baseline ----------

  void _sessionChanged() {
    updateCanvas();
    notifyListeners();
  }

  void attachmentsChanged() {
    _attachmentRevision++;
    updateCanvas();
  }

  void updateCanvas() {
    if (_disposed) return;
    final saved = destination;
    if (saved == null) {
      _comparison = null;
      _setCanvasStatus(uncommitted: false);
      return;
    }
    final snapshot = library.snapshot;
    final file = snapshot.current;
    final baseline = file.githubBaseline;
    final path = snapshot.serializedPath(file.id);
    final document = file.document!;
    final comparison = (
      baseline: baseline,
      document: document,
      path: path,
      fileId: file.id,
      destination: saved,
      attachmentRevision: _attachmentRevision,
    );
    final previous = _comparison;
    if (identical(previous?.document, document) && previous == comparison) return;
    _comparison = comparison;
    if (baseline == null ||
        !baseline.isFor(saved) ||
        baseline.path != path ||
        baseline.documentHash != GitHubBaseline.hashDocument(document)) {
      _setCanvasStatus(uncommitted: true);
      return;
    }
    _setCanvasStatus(
      uncommitted: previous?.fileId == file.id && previous?.destination == saved && _uncommitted,
      checkingAttachments: true,
    );
    unawaited(() async {
      var matches = false;
      try {
        matches = await baseline.matchesAttachments(document, attachmentStore);
      } on Object {
        // Unreadable bytes cannot establish a match.
      }
      if (!_disposed && identical(_comparison, comparison)) _setCanvasStatus(uncommitted: !matches);
    }());
  }

  void _setCanvasStatus({required bool uncommitted, bool checkingAttachments = false}) {
    if (_uncommitted == uncommitted && _checkingAttachments == checkingAttachments) return;
    _uncommitted = uncommitted;
    _checkingAttachments = checkingAttachments;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    finishOverwriteReview(overwrite: false);
    session.dispose();
    super.dispose();
  }
}
