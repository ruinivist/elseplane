// Composes GitHub account, transfer workflows, and the workspace panel.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/github/github_browser.dart';
import 'package:elseplane/github/github_controller.dart';
import 'package:elseplane/github/github_panel.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:flutter/material.dart';

class GitHubWorkspacePanel extends StatefulWidget {
  const GitHubWorkspacePanel({
    required this.api,
    required this.library,
    required this.attachmentStore,
    required this.currentFileId,
    required this.blocked,
    required this.beginTransfer,
    required this.endTransfer,
    required this.onImportTransfer,
    required this.finishInteraction,
    required this.githubAppSlug,
    this.navigateGitHubAuthorization,
    this.consumeGitHubCompletion,
    this.openGitHubLink,
    super.key,
  });

  final GitHubApi api;
  final LibraryController library;
  final AttachmentStore attachmentStore;
  final String currentFileId;
  final bool blocked;
  final bool Function() beginTransfer;
  final VoidCallback endTransfer;
  final Future<TransferImportResult> Function(TransferSource source) onImportTransfer;
  final VoidCallback finishInteraction;
  final String? githubAppSlug;
  final void Function(Uri)? navigateGitHubAuthorization;
  final bool Function()? consumeGitHubCompletion;
  final void Function(String url)? openGitHubLink;

  @override
  State<GitHubWorkspacePanel> createState() => _GitHubWorkspacePanelState();
}

class _GitHubWorkspacePanelState extends State<GitHubWorkspacePanel> {
  late final GitHubController _github = GitHubController(widget.api);
  late final Uri _appInstallationUri;

  @override
  void initState() {
    super.initState();
    final slug = widget.githubAppSlug;
    if (slug == null || slug.isEmpty) {
      throw const FormatException('GITHUB_APP_SLUG must be configured when GitHub is enabled.');
    }
    _appInstallationUri = gitHubAppInstallationUri(slug);
    _github.addListener(_githubChanged);
    widget.library.addListener(_libraryChanged);
    unawaited(_restoreGitHubSession());
  }

  @override
  void didUpdateWidget(covariant GitHubWorkspacePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.library, widget.library)) {
      oldWidget.library.removeListener(_libraryChanged);
      widget.library.addListener(_libraryChanged);
    }
  }

  Future<void> _restoreGitHubSession() async {
    late final bool completion;
    try {
      completion = (widget.consumeGitHubCompletion ?? consumeGitHubCompletion)();
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
      return;
    }
    try {
      await _github.restoreSession();
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
      return;
    }
    if (!mounted) return;
    if (_github.error case final error?) {
      _showMessage(error);
    } else if (_accountMismatch) {
      _showMessage('GitHub account changed. Choose a repository for this account.');
    }
    if (completion && _github.account != null && _github.discoveryError == null && !_hasUsableSavedChoice) {
      widget.finishInteraction();
      await _chooseGitHubRepository();
    }
  }

  bool get _accountMismatch {
    final destination = widget.library.library.githubDestination;
    final account = _github.account;
    return destination != null && account != null && destination.accountId != account.id;
  }

  GitHubRepository? _repositoryForDestination(GitHubDestination? destination) {
    if (destination == null || _github.discoveryError != null) return null;
    for (final repository in _github.repositories) {
      if (repository.id == destination.repositoryId &&
          repository.owner == destination.owner &&
          repository.name == destination.repository) {
        return repository;
      }
    }
    return null;
  }

  GitHubInstallation? _installationForRepository(GitHubRepository repository) {
    for (final installation in _github.installations) {
      if (installation.id == repository.installationId) return installation;
    }
    return null;
  }

  bool get _hasUsableSavedChoice {
    final account = _github.account;
    final destination = widget.library.library.githubDestination;
    if (account == null || destination == null || destination.accountId != account.id) return false;
    final repository = _repositoryForDestination(destination);
    if (repository == null || repository.defaultBranch != destination.branch || !repository.canPull) return false;
    return _installationForRepository(repository)?.canReadContents == true;
  }

  String? _repositoryStatus(GitHubDestination? destination, GitHubRepository? repository) {
    if (destination == null) return null;
    if (_accountMismatch) return 'This saved repository belongs to another GitHub account.';
    if (_github.discoveryLoading) return 'Checking the saved repository access…';
    if (_github.discoveryError != null) return 'Saved repository access could not be verified. Refresh to retry.';
    if (repository == null) return 'Saved repository is unavailable. Change repository or manage access.';
    if (repository.defaultBranch != destination.branch) {
      return 'Default branch changed from ${destination.branch} to ${repository.defaultBranch}. Change repository to confirm.';
    }
    final installation = _installationForRepository(repository);
    if (installation == null || !installation.canReadContents || !repository.canPull) {
      return 'This repository does not have Contents read access. Manage repository access to continue.';
    }
    if (!installation.canWriteContents || !repository.canPush || repository.archived || repository.disabled) {
      return 'This repository is read-only. Imports are available; commits are disabled.';
    }
    return null;
  }

  Future<void> _connectGitHub() async {
    if (!widget.beginTransfer()) return;
    try {
      try {
        await widget.library.flush();
      } on Object {
        _showMessage('Could not save canvas. GitHub authorization was not started.');
        return;
      }
      if (!mounted) return;
      final authorization = await _github.run(_github.api.startAuthorization);
      if (!mounted) return;
      (widget.navigateGitHubAuthorization ?? navigateGitHubAuthorization)(authorization);
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  Future<void> _chooseGitHubRepository() async {
    if (!widget.beginTransfer()) return;
    try {
      await widget.library.flush();
      if (!mounted) return;
      final account = _github.account;
      if (account == null) {
        _showMessage('Connect GitHub to choose a repository.');
        return;
      }
      if (_github.discoveryError != null) {
        _showMessage('Repository discovery failed. Refresh and try again.');
        return;
      }
      if (_github.discoveryLoading) {
        _showMessage('Repository discovery is still running. Try again shortly.');
        return;
      }
      final saved = widget.library.library.githubDestination;
      final savedRepository = saved == null || saved.accountId != account.id
          ? null
          : _github.repositories.where((repository) {
              return repository.id == saved.repositoryId &&
                  repository.owner == saved.owner &&
                  repository.name == saved.repository;
            }).firstOrNull;
      final initialRepositoryId =
          savedRepository?.id ??
          (saved == null && _github.repositories.length == 1 ? _github.repositories.single.id : null);
      final repositoryId = await showGitHubRepositoryDialog(
        context,
        repositories: _github.repositories,
        installations: _github.installations,
        initialRepositoryId: initialRepositoryId,
        onManageAccess: _openAccessChoice,
      );
      if (!mounted || repositoryId == null) return;
      final repository = _github.repositories.where((value) => value.id == repositoryId).firstOrNull;
      if (repository == null || account.id != _github.account?.id) {
        _showMessage('GitHub account or repository list changed. Refresh and choose again.');
        return;
      }
      final destination = await _github.run(() => _github.api.resolveRepository(repository));
      if (!mounted) return;
      if (_github.account?.id != account.id || destination.accountId != account.id) {
        _showMessage('GitHub account changed. The repository was not saved.');
        return;
      }
      await widget.library.setGitHubDestination(destination);
      _showMessage('GitHub repository saved');
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  Future<Uri?> _chooseAccessUri() {
    if (_github.installations.isEmpty) return Future.value(_appInstallationUri);
    return showGitHubAccessDialog(
      context,
      installations: _github.installations,
      installUri: _appInstallationUri,
    );
  }

  Future<void> _openAccessChoice() async {
    try {
      final uri = await _chooseAccessUri();
      if (!mounted || uri == null) return;
      (widget.openGitHubLink ?? openGitHubLink)(uri.toString());
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    }
  }

  Future<void> _manageGitHubAccess() async {
    if (!widget.beginTransfer()) return;
    try {
      await widget.library.flush();
      if (!mounted) return;
      await _openAccessChoice();
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  Future<void> _refreshRepositories() async {
    if (!widget.beginTransfer()) return;
    try {
      await _github.refreshRepositories();
      if (mounted && _github.discoveryError != null) _showMessage(_github.discoveryError!);
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  Future<void> _logoutGitHub() async {
    if (!await confirmGitHubLogout(context) || !mounted || !widget.beginTransfer()) return;
    try {
      await _github.logout();
      _showMessage('GitHub session ended. This does not revoke GitHub authorization.');
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  ({GitHubDestination destination, GitHubRepository repository, int installationId})? _usableGitHubSelection() {
    final destination = widget.library.library.githubDestination;
    final account = _github.account;
    if (account == null) {
      _showMessage('Connect GitHub to continue.');
      return null;
    }
    if (destination == null) {
      _showMessage('Choose a GitHub repository first.');
      return null;
    }
    if (destination.accountId != account.id) {
      _showMessage('Choose a repository for @${account.login} before continuing.');
      return null;
    }
    if (_github.discoveryError != null) {
      _showMessage('Repository access could not be verified. Refresh before transferring.');
      return null;
    }
    final repository = _repositoryForDestination(destination);
    if (repository == null) {
      _showMessage('This repository is no longer available through the GitHub App. Change repository to continue.');
      return null;
    }
    if (repository.defaultBranch != destination.branch) {
      _showMessage('The repository default branch changed. Change repository to confirm it.');
      return null;
    }
    final installation = _installationForRepository(repository);
    if (!repository.canPull || installation?.canReadContents != true) {
      _showMessage('This repository does not have Contents read access. Manage repository access to continue.');
      return null;
    }
    return (destination: destination, repository: repository, installationId: repository.installationId);
  }

  Future<void> _importRepository() async {
    if (!widget.beginTransfer()) return;
    try {
      await widget.library.flush();
      if (!mounted) return;
      final selection = _usableGitHubSelection();
      if (selection == null) return;
      final source = await _github.run(
        () => _github.api.readRepository(selection.destination, installationId: selection.installationId),
      );
      if (!mounted) return;
      await widget.onImportTransfer(source);
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  Future<void> _commitCurrentCanvas() async {
    if (!widget.beginTransfer()) return;
    try {
      await widget.library.flush();
      if (!mounted) return;
      final selection = _usableGitHubSelection();
      if (selection == null) return;
      final installation = _installationForRepository(selection.repository)!;
      if (!installation.canWriteContents ||
          !selection.repository.canPush ||
          selection.repository.archived ||
          selection.repository.disabled) {
        _showMessage('This repository does not allow commits. Check repository permissions and status.');
        return;
      }
      final destination = selection.destination;
      final installationId = selection.installationId;
      final fileId = widget.currentFileId;
      final captured = widget.library.snapshot.select(fileId);
      final path = captured.serializedPath(fileId);
      final message = await showGitHubCommitDialog(
        context,
        repository: '${destination.owner}/${destination.repository}',
        branch: destination.branch,
        newPath: path,
        isValidMessage: isValidGitHubCommitMessage,
      );
      if (!mounted || message == null) return;
      final tree = await encodeTransfer(captured, widget.attachmentStore, TransferScope.currentCanvas);
      if (!mounted) return;
      final result = await _github.run(
        () => _github.api.commitTransfer(
          destination,
          tree,
          installationId: installationId,
          message: message,
        ),
      );
      if (!mounted) return;
      await showGitHubLinkDialog(
        context,
        message: 'Canvas committed to GitHub.',
        url: result.url,
        onOpen: () => (widget.openGitHubLink ?? openGitHubLink)(result.url),
      );
    } on GitHubUnconfirmedCommit catch (error) {
      if (!mounted) return;
      await showGitHubLinkDialog(
        context,
        message: 'The branch update may have succeeded. Submitting again may create a duplicate commit.',
        url: error.url,
        onOpen: () => (widget.openGitHubLink ?? openGitHubLink)(error.url),
      );
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  String _githubErrorMessage(Object error) => switch (error) {
    GitHubApiException(:final message) => message,
    FormatException(:final message) => message,
    StateError(:final message) => message,
    _ => 'GitHub could not complete this action. Check your connection and try again.',
  };

  void _githubChanged() {
    if (mounted) setState(() {});
  }

  void _libraryChanged() {
    if (mounted) setState(() {});
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    widget.library.removeListener(_libraryChanged);
    _github
      ..removeListener(_githubChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = _github.account;
    final destination = widget.library.library.githubDestination;
    final repository = _repositoryForDestination(destination);
    final branchMatches = repository != null && repository.defaultBranch == destination?.branch;
    final installation = repository == null ? null : _installationForRepository(repository);
    final canImport =
        account != null &&
        destination != null &&
        destination.accountId == account.id &&
        !_accountMismatch &&
        repository != null &&
        installation != null &&
        branchMatches &&
        repository.canPull &&
        installation.canReadContents &&
        _github.discoveryError == null;
    final canCommit =
        canImport &&
        installation.canWriteContents &&
        repository.canPush &&
        !repository.archived &&
        !repository.disabled;
    return GitHubPanel(
      accountLogin: account?.login,
      destination: destination,
      repository: repository,
      repositoryStatus: _repositoryStatus(destination, repository),
      connected: account != null,
      busy: _github.busy || widget.blocked,
      canCommit: canCommit,
      canImport: canImport,
      discoveryLoading: _github.discoveryLoading,
      discoveryError: _github.discoveryError,
      logoutNeedsRetry: _github.logoutNeedsRetry,
      statusMessage: _accountMismatch ? 'Account changed. Choose a repository for this account.' : _github.error,
      onBeforeAction: widget.finishInteraction,
      onConnect: _connectGitHub,
      onCommit: _commitCurrentCanvas,
      onImport: _importRepository,
      onChooseRepository: _chooseGitHubRepository,
      onManageAccess: _manageGitHubAccess,
      onRefreshRepositories: _refreshRepositories,
      onLogout: _logoutGitHub,
    );
  }
}
