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
import 'package:elseplane/ui/common/notifications.dart';
import 'package:flutter/material.dart';

// ---------- Workspace workflow ----------

enum GitHubImportPhase { preparing, confirm, saving, result }

final class GitHubImport {
  GitHubImport._(this.destination);

  final GitHubDestination destination;
  final Completer<void> _cancelled = Completer<void>();
  GitHubImportPhase _phase = GitHubImportPhase.preparing;
  String? _result;
  TransferMerge? _merge;

  GitHubImportPhase get phase => _phase;
  int get canvasCount => _merge?.candidate.canvases.length ?? 0;
  Set<String> get overwritePaths => _merge?.overwritePaths ?? const {};
  String? get result => _result;
}

class GitHubSync extends ChangeNotifier {
  GitHubSync({
    required GitHubApi api,
    required this.library,
    required this.attachmentStore,
    required this.notifications,
    required this.beginTransfer,
    required this.endTransfer,
    required this.resumeCanvasInput,
    required this.prepareImport,
    required this.applyImport,
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
  final NotificationController notifications;
  final bool Function() beginTransfer;
  final VoidCallback endTransfer;
  final VoidCallback resumeCanvasInput;
  final Future<TransferMerge?> Function(TransferSource source, bool Function() isCurrent) prepareImport;
  final Future<TransferImportResult> Function(
    TransferMerge merge,
    Set<String> confirmedOverwritePaths,
    GitHubDestination destination,
  )
  applyImport;
  final Uri installUri;
  final void Function(Uri) navigate;
  final bool Function() consumeCompletion;
  final void Function(String) openLink;

  // ---------- State ----------

  var _disposed = false;
  var _refreshRequired = false;
  var _commitInProgress = false;
  String? _progress;
  String? message;
  GitHubImport? _importAttempt;
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
  bool get busy => _progress != null || session.busy || _importAttempt != null;
  bool get commitInProgress => _commitInProgress;
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

  bool rejectDuringCommit() {
    if (!_commitInProgress) return false;
    notifications.show('Wait for the current commit to finish, then try again.');
    return true;
  }

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

  // ---------- Transfers ----------

  GitHubImport? startImport() {
    if (rejectDuringCommit() || _disposed || busy || !canImport) return null;
    final saved = destination;
    final repo = _readableRepository;
    if (saved == null || repo == null) return null;
    final attempt = GitHubImport._(saved);
    _importAttempt = attempt;
    notifyListeners();
    unawaited(_prepareImport(attempt, repo.installationId));
    return attempt;
  }

  void confirmImport(GitHubImport attempt) {
    if (!_isCurrentImport(attempt) || attempt.phase != GitHubImportPhase.confirm) return;
    final merge = attempt._merge;
    if (merge == null) return;
    if (!beginTransfer()) {
      _setImportResult(
        attempt,
        'Another workspace transfer is in progress. Wait for it to finish, then start the import again.',
      );
      return;
    }
    attempt._phase = GitHubImportPhase.saving;
    notifyListeners();
    unawaited(_applyImport(attempt, merge));
  }

  void closeImport(GitHubImport attempt) {
    if (!_isCurrentImport(attempt) || attempt.phase == GitHubImportPhase.saving) return;
    _importAttempt = null;
    _cancelImport(attempt);
    notifyListeners();
  }

  Future<void> _prepareImport(GitHubImport attempt, int installationId) async {
    try {
      final source = await session.run<TransferSource?>(() async {
        try {
          final source = await Future.any<TransferSource?>([
            session.api
                .readRepository(
                  attempt.destination,
                  installationId: installationId,
                  isCurrent: () => _isPreparingImport(attempt),
                )
                .then<TransferSource?>((source) => source),
            attempt._cancelled.future.then<TransferSource?>((_) => null),
          ]);
          if (!_isCurrentImport(attempt)) throw const _GitHubImportCancelled();
          return source;
        } on Object {
          if (!_isCurrentImport(attempt)) throw const _GitHubImportCancelled();
          rethrow;
        }
      });
      if (!_isCurrentImport(attempt)) return;
      if (source == null) {
        _setImportResult(attempt, 'Could not prepare the GitHub import. Try again.');
        return;
      }
      final merge = await prepareImport(source, () => _isPreparingImport(attempt));
      if (!_isCurrentImport(attempt)) return;
      if (merge == null) {
        _setImportResult(attempt, 'Could not prepare the GitHub import. Try again.');
        return;
      }
      attempt._merge = merge;
      if (attempt.canvasCount == 0) {
        _setImportResult(attempt, _formatEmptyImport(merge.candidate.skippedCanvases));
      } else {
        attempt._phase = GitHubImportPhase.confirm;
        notifyListeners();
      }
    } on Object catch (error) {
      if (!_isCurrentImport(attempt)) return;
      if (error is GitHubDefaultBranchChanged) _refreshRequired = true;
      _setImportResult(attempt, _errorMessage(error));
    }
  }

  Future<void> _applyImport(GitHubImport attempt, TransferMerge merge) async {
    try {
      if (!_isCurrentImport(attempt)) return;
      final result = await applyImport(merge, merge.overwritePaths, attempt.destination);
      if (!_isCurrentImport(attempt)) return;
      _setImportResult(
        attempt,
        _formatImportResult(result, attempt.canvasCount),
      );
    } on Object catch (error) {
      if (!_isCurrentImport(attempt)) return;
      _setImportResult(attempt, _errorMessage(error));
    } finally {
      endTransfer();
    }
  }

  bool _isCurrentImport(GitHubImport attempt) => !_disposed && identical(_importAttempt, attempt);

  bool _isPreparingImport(GitHubImport attempt) =>
      _isCurrentImport(attempt) && attempt.phase == GitHubImportPhase.preparing;

  void _cancelImport(GitHubImport attempt) {
    if (!attempt._cancelled.isCompleted) attempt._cancelled.complete();
  }

  void _setImportResult(GitHubImport attempt, String result) {
    if (!_isCurrentImport(attempt)) return;
    attempt
      .._result = result
      .._phase = GitHubImportPhase.result;
    notifyListeners();
  }

  String _formatEmptyImport(List<TransferIssue> skipped) {
    final lines = ['No canvases to import.'];
    _appendSkippedCanvases(lines, skipped);
    return lines.join('\n');
  }

  String _formatImportResult(TransferImportResult result, int canvasCount) {
    final lines = <String>[];
    if (result.metadataSaved) {
      lines.add('Imported $canvasCount ${canvasCount == 1 ? 'canvas' : 'canvases'}.');
    } else if (result.failure case final failure?) {
      if (failure.stage == TransferFailureStage.imageWrite ||
          (failure.stage == TransferFailureStage.publication && result.writtenImagePaths.isNotEmpty)) {
        lines.add('Images may have changed; imported canvases were not saved.');
      }
      lines.add('${failure.reason}${failure.path == null ? '' : ': ${failure.path}'}');
    } else if (result.writtenImagePaths.isNotEmpty) {
      lines.add('Images changed; the library metadata was unchanged.');
    } else {
      lines.add('No canvases to import.');
    }
    _appendSkippedCanvases(lines, result.skippedCanvases);
    return lines.join('\n');
  }

  void _appendSkippedCanvases(List<String> lines, List<TransferIssue> skipped) {
    if (skipped.isEmpty) return;
    lines
      ..add('Skipped canvases:')
      ..addAll(skipped.map((issue) => '${issue.path}: ${issue.reason}'));
  }

  Future<void> commit(BuildContext context) async {
    if (rejectDuringCommit() || !canCommitCurrent) return;
    NotificationOperation? notification;
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
        final progress = notification = notifications.begin('Committing canvas…');
        final tree = await encodeTransfer(captured, attachmentStore, TransferScope.currentCanvas);
        if (_disposed) return;
        final baseline = GitHubBaseline.capture(saved, path, captured.current.document!, tree.files);
        resumeCanvasInput();
        await session.run(
          () => session.api.commitTransfer(saved, tree, installationId: repo.installationId, message: message),
        );
        if (_disposed) return;
        var feedback = 'Canvas committed to GitHub.';
        var severity = NotificationSeverity.success;
        try {
          await library.saveGitHubBaseline(captured.currentId, baseline);
        } on Object {
          feedback = 'Canvas committed to GitHub. Could not save its local sync baseline.';
          severity = NotificationSeverity.warning;
        }
        if (context.mounted) {
          progress.complete(
            feedback,
            severity: severity,
          );
        }
      },
      commitOnly: true,
      onError: (error) {
        if (!context.mounted || _disposed) return;
        final String text;
        final NotificationSeverity severity;
        final NotificationAction? action;
        if (error is GitHubUnconfirmedCommit) {
          text = 'The branch update may have succeeded. Submitting again may create a duplicate commit.';
          severity = NotificationSeverity.warning;
          action = NotificationAction(label: 'Check GitHub', onPressed: () => openLink(error.url));
        } else {
          text = _errorMessage(error);
          severity = NotificationSeverity.error;
          action = null;
        }
        if (notification case final progress?) {
          progress.complete(text, severity: severity, action: action);
        } else {
          notifications.show(text, severity: severity, action: action);
        }
      },
    );
  }

  Future<void> _run(
    String progress,
    Future<void> Function() operation, {
    bool commitOnly = false,
    void Function(Object)? onError,
  }) async {
    if (_disposed || busy || !beginTransfer()) return;
    if (commitOnly) _commitInProgress = true;
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
      if (commitOnly) _commitInProgress = false;
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
    final attempt = _importAttempt;
    _importAttempt = null;
    if (attempt != null) _cancelImport(attempt);
    session.dispose();
    super.dispose();
  }
}

final class _GitHubImportCancelled implements Exception {
  const _GitHubImportCancelled();
}
