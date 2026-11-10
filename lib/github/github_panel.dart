// Presents manual GitHub actions for the current canvas workspace.

import 'dart:async';

import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/material.dart';

class GitHubPanel extends StatelessWidget {
  const GitHubPanel({
    required this.accountLogin,
    required this.destination,
    required this.connected,
    required this.busy,
    required this.canCommit,
    required this.canOpen,
    required this.pendingWrite,
    required this.logoutNeedsRetry,
    required this.onBeforeAction,
    required this.onConnect,
    required this.onCommit,
    required this.onOpen,
    required this.onChooseRepository,
    required this.onLogout,
    required this.onCheckRemoteStatus,
    this.statusMessage,
    super.key,
  });

  final String? accountLogin;
  final GitHubDestination? destination;
  final bool connected;
  final bool busy;
  final bool canCommit;
  final bool canOpen;
  final bool pendingWrite;
  final bool logoutNeedsRetry;
  final String? statusMessage;
  final VoidCallback onBeforeAction;
  final Future<void> Function() onConnect;
  final Future<void> Function() onCommit;
  final Future<void> Function() onOpen;
  final Future<void> Function() onChooseRepository;
  final Future<void> Function() onLogout;
  final Future<void> Function() onCheckRemoteStatus;

  VoidCallback? _action(Future<void> Function()? action) => action == null || busy
      ? null
      : () {
          onBeforeAction();
          unawaited(action());
        };

  @override
  Widget build(BuildContext context) {
    final accountLogin = this.accountLogin;
    final destination = this.destination;
    final theme = BTheme.of(context);
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Surface(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!connected) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('github-connect'),
                      onPressed: _action(logoutNeedsRetry ? null : onConnect),
                      icon: const Icon(Icons.link),
                      label: const Text('Connect GitHub'),
                    ),
                  ),
                  if (logoutNeedsRetry)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const ValueKey('github-logout-retry'),
                        onPressed: _action(onLogout),
                        child: const Text('Retry logout'),
                      ),
                    ),
                ] else ...[
                  if (statusMessage != null) ...[
                    Text(statusMessage!, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    '@$accountLogin${destination == null ? '' : ' · ${destination.owner}/${destination.repository} · ${destination.branch}'}',
                    style: theme.typo.label.copyWith(color: theme.colors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  if (destination != null) ...[
                    FilledButton.tonal(
                      key: const ValueKey('github-commit'),
                      onPressed: _action(canCommit ? onCommit : null),
                      child: const Text('Commit current canvas'),
                    ),
                    TextButton(
                      key: const ValueKey('github-open'),
                      onPressed: _action(canOpen ? onOpen : null),
                      child: const Text('Open from GitHub'),
                    ),
                    if (pendingWrite) ...[
                      const Text(
                        'Check remote status before retrying a failed or unconfirmed write. If it conflicts, open the remote copy as another canvas.',
                      ),
                      TextButton(
                        key: const ValueKey('github-check-remote'),
                        onPressed: _action(onCheckRemoteStatus),
                        child: const Text('Check remote status'),
                      ),
                    ],
                  ],
                  Row(
                    children: [
                      TextButton(
                        key: const ValueKey('github-repository'),
                        onPressed: _action(onChooseRepository),
                        child: const Text('Repository…'),
                      ),
                      const Spacer(),
                      TextButton(
                        key: const ValueKey('github-logout'),
                        onPressed: _action(onLogout),
                        child: const Text('Log out'),
                      ),
                    ],
                  ),
                ],
                if (!connected && statusMessage != null) Text(statusMessage!),
                if (busy) ...[
                  const SizedBox(height: 4),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> showGitHubRepositoryDialog(BuildContext context, {required String initial}) async {
  final formKey = GlobalKey<FormState>();
  final field = TextEditingController(text: initial);
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => SurfaceDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Choose a GitHub repository', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        const Text('Enter owner/repository. Elseplane uses its default branch.'),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('github-repository-field'),
                          controller: field,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: 'owner/repository'),
                          validator: (value) {
                            final parts = (value ?? '').trim().split('/');
                            final valid =
                                parts.length == 2 &&
                                parts.every((part) => RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(part)) &&
                                parts.every((part) => part != '.' && part != '..');
                            return valid ? null : 'Enter owner/repository';
                          },
                          onFieldSubmitted: (_) {
                            if (formKey.currentState!.validate()) Navigator.pop(context, field.text.trim());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) Navigator.pop(context, field.text.trim());
                      },
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    field.dispose();
  }
}

Future<bool> confirmGitHubDestination(
  BuildContext context, {
  required String ownerRepository,
  required String branch,
  required bool isPrivate,
  required bool resetsTracking,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => SurfaceConfirmationDialog(
        title: const Text('Use this repository?'),
        content: Text(
          '$ownerRepository is ${isPrivate ? 'private' : 'public'} and uses default branch “$branch”.'
          '${resetsTracking ? ' Changing the destination clears saved GitHub links for every local canvas.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Use repository')),
        ],
      ),
    ) ??
    false;

Future<String?> showGitHubCommitDialog(
  BuildContext context, {
  required String repository,
  required String branch,
  required String? oldPath,
  required String newPath,
  required bool Function(String) isValidMessage,
}) async {
  final field = TextEditingController(text: 'docs: save canvas');
  final formKey = GlobalKey<FormState>();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => SurfaceDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Commit current canvas', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        Text('$repository · $branch'),
                        if (oldPath != null) Text('From: $oldPath'),
                        Text('To: $newPath'),
                        const SizedBox(height: 16),
                        const Text('Completed canvas edits are saved before this commit.'),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('github-commit-message'),
                          controller: field,
                          autofocus: true,
                          maxLength: 72,
                          decoration: const InputDecoration(labelText: 'Commit message'),
                          validator: (value) => isValidMessage(value ?? '')
                              ? null
                              : 'Use a lowercase Conventional Commit subject (72 characters max).',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) Navigator.pop(context, field.text);
                      },
                      child: const Text('Commit'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    field.dispose();
  }
}

Future<String?> showGitHubCanvasDialog(BuildContext context, List<String> paths) => showDialog<String>(
  context: context,
  builder: (context) => SurfaceConfirmationDialog(
    title: const Text('Open a GitHub canvas'),
    content: paths.isEmpty
        ? const Text('This repository has no regular .canvas files.')
        : ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final path in paths)
                    TextButton(
                      key: ValueKey('github-canvas-$path'),
                      onPressed: () => Navigator.pop(context, path),
                      child: Align(alignment: Alignment.centerLeft, child: Text(path)),
                    ),
                ],
              ),
            ),
          ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
  ),
);

Future<String?> showGitHubCanvasNameDialog(
  BuildContext context, {
  required String initial,
  required String message,
}) async {
  final field = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => SurfaceDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Choose a local canvas name', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        Text(message),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('github-canvas-name'),
                          controller: field,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: 'Canvas name'),
                          validator: (value) => (value ?? '').trim().isEmpty ? 'Enter a name' : null,
                          onFieldSubmitted: (_) {
                            if (formKey.currentState!.validate()) Navigator.pop(context, field.text.trim());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) Navigator.pop(context, field.text.trim());
                      },
                      child: const Text('Import'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    field.dispose();
  }
}

Future<bool> confirmGitHubLogout(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => SurfaceConfirmationDialog(
        title: const Text('Log out of GitHub?'),
        content: const Text('This ends the local session but does not revoke GitHub authorization.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
        ],
      ),
    ) ??
    false;

enum GitHubConflictAction { cancel, openRemote, renameLocal }

Future<GitHubConflictAction> showGitHubConflictDialog(
  BuildContext context, {
  required String message,
  required bool canRename,
}) async =>
    await showDialog<GitHubConflictAction>(
      context: context,
      builder: (context) => SurfaceConfirmationDialog(
        title: const Text('GitHub conflict'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, GitHubConflictAction.cancel),
            child: const Text('Cancel'),
          ),
          if (canRename)
            TextButton(
              onPressed: () => Navigator.pop(context, GitHubConflictAction.renameLocal),
              child: const Text('Choose another name'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, GitHubConflictAction.openRemote),
            child: const Text('Open remote copy'),
          ),
        ],
      ),
    ) ??
    GitHubConflictAction.cancel;

Future<void> showGitHubLinkDialog(
  BuildContext context, {
  required String message,
  required String url,
  required VoidCallback onOpen,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => SurfaceConfirmationDialog(
      title: const Text('GitHub'),
      content: SelectableText('$message\n$url'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onOpen();
          },
          child: const Text('Open on GitHub'),
        ),
      ],
    ),
  );
}
