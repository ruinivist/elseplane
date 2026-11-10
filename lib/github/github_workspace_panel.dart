// Composes GitHub account, transfer workflows, and the workspace panel.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/github/github_browser.dart';
import 'package:elseplane/github/github_controller.dart';
import 'package:elseplane/github/github_panel.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/transfer/canvas_remote_transfer.dart';
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
    required this.onImported,
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
  final VoidCallback onImported;
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
      _showMessage('GitHub account changed. Choose a repository to reset canvas tracking.');
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
      final previous = widget.library.library.githubDestination;
      final resetsTracking =
          previous == null ||
          previous.accountId != destination.accountId ||
          previous.repositoryId != destination.repositoryId ||
          previous.owner.toLowerCase() != destination.owner.toLowerCase() ||
          previous.repository.toLowerCase() != destination.repository.toLowerCase() ||
          previous.branch != destination.branch;
      if (!await confirmGitHubDestination(
        context,
        ownerRepository: '${destination.owner}/${destination.repository}',
        branch: destination.branch,
        isPrivate: _github.api.lastRepositoryPrivate ?? false,
        resetsTracking: resetsTracking,
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

  Future<void> _openGitHubCanvas() async {
    if (!widget.beginTransfer()) return;
    try {
      await widget.library.flush();
      if (!mounted) return;
      final destination = _usableGitHubDestination();
      if (destination == null) return;
      final snapshot = await _github.run(() => _github.api.snapshot(destination));
      if (!mounted) return;
      final path = await showGitHubCanvasDialog(context, snapshot.canvasPaths);
      if (!mounted || path == null) return;
      await _importGitHubCanvas(destination, snapshot, path);
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  Future<void> _importGitHubCanvas(GitHubDestination destination, GitHubSnapshot snapshot, String path) async {
    final project = await _github.run(() => _github.api.openCanvas(destination, snapshot, path));
    if (!mounted) return;
    final tracking = _github.api.trackingForCanvas(snapshot, path, project);
    final segments = path.split('/');
    final folders = segments.take(segments.length - 1).toList();
    final defaultName = segments.last.substring(0, segments.last.length - '.canvas'.length);
    final parentId = _localFolderId(folders);
    final parentExists = folders.isEmpty || parentId != null;
    var name = defaultName;
    if (parentExists && widget.library.library.nameError(name, parentId) != null) {
      final chosen = await showGitHubCanvasNameDialog(
        context,
        initial: name,
        message: 'A local canvas or folder already uses this name in the matching folder.',
      );
      if (!mounted || chosen == null) return;
      name = chosen;
      if (parentExists && widget.library.library.nameError(name, parentId) != null) {
        _showMessage('This name is already in use. Choose another local name.');
        return;
      }
    }
    final clearPendingFileId = widget.library.library.files
        .where(
          (file) =>
              file.githubWriteUnconfirmed &&
              (file.githubPendingTracking?.path == path || file.githubTracking?.path == path),
        )
        .firstOrNull
        ?.id;
    await widget.library.addGitHubCanvas(
      folders: folders,
      name: name,
      project: project,
      tracking: tracking,
      clearPendingFileId: clearPendingFileId,
    );
    if (mounted) {
      widget.onImported();
      _showMessage('Canvas opened from GitHub');
    }
  }

  String? _localFolderId(List<String> folders) {
    String? parentId;
    for (final name in folders) {
      final sibling = widget.library.library.files
          .where((file) => file.parentId == parentId && file.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (sibling == null) return null;
      if (!sibling.isFolder) throw FormatException('A canvas blocks the required folder “$name”.');
      parentId = sibling.id;
    }
    return parentId;
  }

  Future<void> _checkPendingRemote() async {
    if (!widget.beginTransfer()) return;
    final fileId = widget.currentFileId;
    final file = widget.library.library.file(fileId);
    final tracking = file.githubTracking;
    final pendingTracking = file.githubPendingTracking;
    GitHubDestination? destination;
    try {
      if (pendingTracking == null) return;
      await widget.library.flush();
      if (!mounted) return;
      destination = _usableGitHubDestination();
      if (destination == null) return;
      final checkedTracking = await _github.run(
        () => widget.api.checkPendingWrite(
          destination!,
          tracking: tracking,
          pendingTracking: pendingTracking,
        ),
      );
      if (!mounted) return;
      await widget.library.setGitHubTracking(fileId, checkedTracking);
      _showMessage('Remote status verified. You can commit this canvas again.');
    } on GitHubConflict catch (error) {
      if (!mounted) return;
      final action = await showGitHubConflictDialog(context, message: error.message, canRename: false);
      if (mounted && action == GitHubConflictAction.openRemote && destination != null) {
        await _openRemoteConflict(destination, pendingTracking?.path ?? tracking?.path);
      }
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  Future<void> _commitCurrentCanvas() async {
    if (!widget.beginTransfer()) return;
    var refUpdateStarted = false;
    var remoteSucceeded = false;
    GitHubCanvasTracking? originalTracking;
    String? capturedFileId;
    String? capturedRemotePath;
    try {
      await widget.library.flush();
      if (!mounted) return;
      final destination = _usableGitHubDestination();
      if (destination == null) return;
      final fileId = capturedFileId = widget.currentFileId;
      final file = widget.library.library.file(fileId);
      if (file.githubWriteUnconfirmed) {
        _showMessage('Check remote status before writing this canvas again.');
        return;
      }
      final document = file.document!;
      originalTracking = file.githubTracking;
      final path = capturedRemotePath = canvasRemotePath(widget.library.library, fileId);
      final message = await showGitHubCommitDialog(
        context,
        repository: '${destination.owner}/${destination.repository}',
        branch: destination.branch,
        oldPath: originalTracking?.path,
        newPath: path,
        isValidMessage: isValidGitHubCommitMessage,
      );
      if (!mounted || message == null) return;
      final project = await prepareCanvasRemoteTransfer(document, widget.attachmentStore);
      if (!mounted) return;
      final result = await _github.run(
        () => _github.api.commitCanvas(
          destination: destination,
          path: path,
          project: project,
          tracking: originalTracking,
          message: message,
          beforeRefUpdate: (commitSha, tracking) async {
            try {
              await widget.library.setGitHubTracking(
                fileId,
                originalTracking,
                pendingTracking: tracking,
              );
              refUpdateStarted = true;
            } on Object {
              throw StateError('Could not save the GitHub write guard. No branch update was sent.');
            }
          },
        ),
      );
      remoteSucceeded = !result.noChanges;
      try {
        await widget.library.setGitHubTracking(fileId, result.tracking);
      } on Object catch (error) {
        if (result.noChanges) {
          _showMessage('No remote changes. Could not save GitHub tracking: ${_githubErrorMessage(error)}');
        } else {
          if (!mounted) return;
          await showGitHubLinkDialog(
            context,
            message: 'GitHub accepted the commit, but local tracking could not be saved. Check remote status before writing again.',
            url: result.url,
            onOpen: () => (widget.openGitHubLink ?? openGitHubLink)(result.url),
          );
        }
        return;
      }
      if (!mounted) return;
      await showGitHubLinkDialog(
        context,
        message: result.noChanges ? 'No changes to commit.' : 'Canvas committed to GitHub.',
        url: result.url,
        onOpen: () => (widget.openGitHubLink ?? openGitHubLink)(result.url),
      );
    } on GitHubUnconfirmedCommit catch (error) {
      if (!mounted) return;
      await showGitHubLinkDialog(
        context,
        message: 'The branch update may have succeeded. Check remote status before writing again.',
        url: error.url,
        onOpen: () => (widget.openGitHubLink ?? openGitHubLink)(error.url),
      );
    } on GitHubConflict catch (error) {
      if (refUpdateStarted && capturedFileId != null) {
        try {
          await widget.library.setGitHubTracking(capturedFileId, originalTracking);
        } on Object {
          _showMessage('GitHub conflict. The write guard could not be cleared; your canvas is preserved.');
          return;
        }
      }
      if (!mounted) return;
      final currentFile = capturedFileId == null ? null : widget.library.library.file(capturedFileId);
      final action = await showGitHubConflictDialog(
        context,
        message: error.message,
        canRename: currentFile != null && originalTracking == null,
      );
      if (!mounted) return;
      if (action == GitHubConflictAction.renameLocal && currentFile != null) {
        final name = await showGitHubCanvasNameDialog(
          context,
          initial: currentFile.name,
          message: 'Choose another local name, then commit the canvas again.',
        );
        if (mounted && name != null) {
          final nameError = widget.library.library.nameError(name, currentFile.parentId, exceptId: currentFile.id);
          if (nameError != null) {
            _showMessage(nameError);
          } else {
            await widget.library.rename(currentFile.id, name, openId: currentFile.id);
          }
        }
      } else if (action == GitHubConflictAction.openRemote) {
        final destination = widget.library.library.githubDestination;
        final preferredPath = error.path?.endsWith('.canvas') == true
            ? error.path
            : originalTracking?.path ?? capturedRemotePath;
        if (mounted && destination != null) await _openRemoteConflict(destination, preferredPath);
      }
    } on GitHubApiException catch (error) {
      if (refUpdateStarted &&
          !remoteSucceeded &&
          error.kind != GitHubErrorKind.network &&
          error.kind != GitHubErrorKind.server &&
          capturedFileId != null) {
        try {
          await widget.library.setGitHubTracking(capturedFileId, originalTracking);
        } on Object {
          _showMessage('GitHub request failed. The write guard could not be cleared; check remote status first.');
          return;
        }
      }
      _showMessage(error.message);
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
    } finally {
      widget.endTransfer();
    }
  }

  Future<void> _openRemoteConflict(GitHubDestination destination, String? preferredPath) async {
    try {
      final snapshot = await _github.run(() => _github.api.snapshot(destination));
      if (!mounted) return;
      final path = preferredPath != null && snapshot.canvasPaths.contains(preferredPath)
          ? preferredPath
          : await showGitHubCanvasDialog(context, snapshot.canvasPaths);
      if (!mounted || path == null) return;
      await _importGitHubCanvas(destination, snapshot, path);
    } on Object catch (error) {
      _showMessage(_githubErrorMessage(error));
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
    final current = library.file(widget.currentFileId);
    final canUseDestination = account != null && destination != null && account.id == destination.accountId;
    return GitHubPanel(
      accountLogin: account?.login,
      destination: destination,
      connected: account != null,
      busy: _github.busy || widget.blocked,
      canCommit: canUseDestination && !current.githubWriteUnconfirmed,
      canOpen: canUseDestination,
      pendingWrite: current.githubWriteUnconfirmed,
      logoutNeedsRetry: _github.logoutNeedsRetry,
      statusMessage: _accountMismatch
          ? 'Account changed. Choose a repository to reset canvas tracking.'
          : _github.error,
      onBeforeAction: widget.finishInteraction,
      onConnect: _connectGitHub,
      onCommit: _commitCurrentCanvas,
      onOpen: _openGitHubCanvas,
      onChooseRepository: _chooseGitHubRepository,
      onLogout: _logoutGitHub,
      onCheckRemoteStatus: _checkPendingRemote,
    );
  }
}
