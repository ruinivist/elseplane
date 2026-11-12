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
  final void Function(Uri)? navigateGitHubAuthorization;
  final bool Function()? consumeGitHubCompletion;
  final void Function(String url)? openGitHubLink;

  @override
  State<GitHubWorkspacePanel> createState() => _GitHubWorkspacePanelState();
}

class _GitHubWorkspacePanelState extends State<GitHubWorkspacePanel> {
  late final GitHubController _github = GitHubController(widget.api);

  @override
  void initState() {
    super.initState();
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
    final shouldCheck = completion || widget.library.library.githubDestination != null;
    try {
      await _github.restoreSession(shouldCheck: shouldCheck);
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
      return;
    }
    if (!mounted || !shouldCheck) return;
    if (_github.error case final error?) {
      _showMessage(error);
    } else if (_accountMismatch) {
      _showMessage('GitHub account changed. Choose a repository for this account.');
    }
  }

  bool get _accountMismatch {
    final destination = widget.library.library.githubDestination;
    final account = _github.account;
    return destination != null && account != null && destination.accountId != account.id;
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
      final saved = widget.library.library.githubDestination;
      final ownerRepository = await showGitHubRepositoryDialog(
        context,
        initial: saved == null ? '' : '${saved.owner}/${saved.repository}',
      );
      if (!mounted || ownerRepository == null || _github.account == null) return;
      final destination = await _github.run(() => _github.api.repository(ownerRepository));
      if (!mounted) return;
      if (!await confirmGitHubDestination(
        context,
        ownerRepository: '${destination.owner}/${destination.repository}',
        branch: destination.branch,
        isPrivate: _github.api.lastRepositoryPrivate ?? false,
      )) {
        return;
      }
      if (!mounted) return;
      await widget.library.setGitHubDestination(destination);
      _showMessage('GitHub repository saved');
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

  GitHubDestination? _usableGitHubDestination() {
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
    return destination;
  }

  Future<void> _importRepository() async {
    if (!widget.beginTransfer()) return;
    try {
      await widget.library.flush();
      if (!mounted) return;
      final destination = _usableGitHubDestination();
      if (destination == null) return;
      final source = await _github.run(() => _github.api.readRepository(destination));
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
      final destination = _usableGitHubDestination();
      if (destination == null) return;
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
        () => _github.api.commitTransfer(destination, tree, message: message),
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
    final library = widget.library.library;
    final destination = library.githubDestination;
    final canUseDestination = account != null && destination != null && account.id == destination.accountId;
    return GitHubPanel(
      accountLogin: account?.login,
      destination: destination,
      connected: account != null,
      busy: _github.busy || widget.blocked,
      canCommit: canUseDestination,
      canImport: canUseDestination,
      logoutNeedsRetry: _github.logoutNeedsRetry,
      statusMessage: _accountMismatch ? 'Account changed. Choose a repository for this account.' : _github.error,
      onBeforeAction: widget.finishInteraction,
      onConnect: _connectGitHub,
      onCommit: _commitCurrentCanvas,
      onImport: _importRepository,
      onChooseRepository: _chooseGitHubRepository,
      onLogout: _logoutGitHub,
    );
  }
}
