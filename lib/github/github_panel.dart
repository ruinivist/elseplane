// Presents manual GitHub actions for the current canvas workspace.

import 'dart:async';

import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/material.dart';

class GitHubPanel extends StatelessWidget {
  const GitHubPanel({
    required this.accountLogin,
    required this.destination,
    required this.repository,
    required this.repositoryStatus,
    required this.connected,
    required this.busy,
    required this.canCommit,
    required this.canImport,
    required this.discoveryLoading,
    required this.logoutNeedsRetry,
    required this.onBeforeAction,
    required this.onConnect,
    required this.onCommit,
    required this.onImport,
    required this.onChooseRepository,
    required this.onManageAccess,
    required this.onRefreshRepositories,
    required this.onLogout,
    this.statusMessage,
    this.discoveryError,
    super.key,
  });

  final String? accountLogin;
  final GitHubDestination? destination;
  final GitHubRepository? repository;
  final String? repositoryStatus;
  final bool connected;
  final bool busy;
  final bool canCommit;
  final bool canImport;
  final bool discoveryLoading;
  final bool logoutNeedsRetry;
  final String? statusMessage;
  final String? discoveryError;
  final VoidCallback onBeforeAction;
  final Future<void> Function() onConnect;
  final Future<void> Function() onCommit;
  final Future<void> Function() onImport;
  final Future<void> Function() onChooseRepository;
  final Future<void> Function() onManageAccess;
  final Future<void> Function() onRefreshRepositories;
  final Future<void> Function() onLogout;

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
    final repository = this.repository;
    final theme = BTheme.of(context);
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
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
                  if (statusMessage != null) Text(statusMessage!, style: Theme.of(context).textTheme.bodySmall),
                ] else ...[
                  Text('@$accountLogin', style: theme.typo.label.copyWith(color: theme.colors.textPrimary)),
                  const SizedBox(height: 8),
                  if (destination != null) ...[
                    Text('${destination.owner}/${destination.repository}', style: theme.typo.body),
                    Text(
                      repository == null
                          ? 'Saved default branch: ${destination.branch}'
                          : '${repository.isPrivate ? 'Private' : 'Public'} · default branch: ${repository.defaultBranch}',
                      style: theme.typo.body.copyWith(fontSize: 12, color: theme.colors.textSecondary),
                    ),
                    if (repositoryStatus != null) ...[
                      const SizedBox(height: 4),
                      Text(repositoryStatus!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      key: const ValueKey('github-commit'),
                      onPressed: _action(canCommit ? onCommit : null),
                      child: const Text('Commit current canvas'),
                    ),
                    TextButton(
                      key: const ValueKey('github-import'),
                      onPressed: _action(canImport ? onImport : null),
                      child: const Text('Import repository'),
                    ),
                  ] else ...[
                    if (repositoryStatus != null) ...[
                      Text(repositoryStatus!, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (discoveryError != null) ...[
                    Text(discoveryError!, style: Theme.of(context).textTheme.bodySmall),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const ValueKey('github-refresh-repositories'),
                        onPressed: _action(onRefreshRepositories),
                        child: const Text('Retry repository discovery'),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        TextButton(
                          key: const ValueKey('github-refresh-repositories'),
                          onPressed: _action(discoveryLoading ? null : onRefreshRepositories),
                          child: const Text('Refresh repositories'),
                        ),
                        if (discoveryLoading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator()),
                      ],
                    ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton(
                        key: const ValueKey('github-repository'),
                        onPressed: _action(discoveryLoading || discoveryError != null ? null : onChooseRepository),
                        child: Text(destination == null ? 'Choose repository' : 'Change repository'),
                      ),
                      TextButton(
                        key: const ValueKey('github-manage-access'),
                        onPressed: _action(discoveryLoading ? null : onManageAccess),
                        child: const Text('Manage access'),
                      ),
                    ],
                  ),
                  if (statusMessage != null) ...[
                    Text(statusMessage!, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('github-logout'),
                      onPressed: _action(onLogout),
                      child: const Text('Log out'),
                    ),
                  ),
                ],
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

Future<int?> showGitHubRepositoryDialog(
  BuildContext context, {
  required List<GitHubRepository> repositories,
  required List<GitHubInstallation> installations,
  required int? initialRepositoryId,
  required Future<void> Function() onManageAccess,
}) async {
  final installationById = {for (final installation in installations) installation.id: installation};
  final repositoryById = {for (final repository in repositories) repository.id: repository};
  final options = <SelectOption<int?>>[
    const SelectOption(value: null, label: 'Choose a repository'),
    for (final repository in repositories) SelectOption(value: repository.id, label: repository.fullName),
  ];
  var selectedRepositoryId = repositoryById.containsKey(initialRepositoryId) ? initialRepositoryId : null;

  void submit(BuildContext context) {
    if (selectedRepositoryId != null) Navigator.pop(context, selectedRepositoryId);
  }

  return await showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final repository = repositoryById[selectedRepositoryId];
        final installation = repository == null ? null : installationById[repository.installationId];
        final canRead = repository != null && repository.canPull && installation?.canReadContents == true;
        return SurfaceDialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 280,
              maxWidth: 480,
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Choose a GitHub repository', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        const Text('Search authorized repositories. Search text is not a repository address.'),
                        const SizedBox(height: 12),
                        Semantics(
                          label: 'GitHub repository',
                          child: SearchableSelect<int?>(
                            key: const ValueKey('github-repository-select'),
                            value: selectedRepositoryId,
                            options: options,
                            searchHint: 'Search repositories',
                            onChanged: (value) => setState(() => selectedRepositoryId = value),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (repository == null)
                          Text(
                            repositories.isEmpty
                                ? 'No repositories are available through this GitHub App. Manage access or install the app on another account.'
                                : 'Choose an authorized repository.',
                          )
                        else ...[
                          Text(
                            '${repository.isPrivate ? 'Private' : 'Public'} · default branch: ${repository.defaultBranch}',
                          ),
                          if (!canRead) ...[
                            const SizedBox(height: 8),
                            const Text('This repository does not have Contents read access through its installation.'),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const ValueKey('github-setup-manage-access'),
                                onPressed: () => unawaited(onManageAccess()),
                                child: const Text('Manage repository access'),
                              ),
                            ),
                          ],
                        ],
                        if (repository == null && repositories.isEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: const ValueKey('github-setup-manage-access'),
                              onPressed: () => unawaited(onManageAccess()),
                              child: const Text('Manage repository access'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                        FilledButton(
                          key: const ValueKey('github-use-repository'),
                          onPressed: canRead ? () => submit(context) : null,
                          child: const Text('Use repository'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<Uri?> showGitHubAccessDialog(
  BuildContext context, {
  required List<GitHubInstallation> installations,
  required Uri installUri,
}) async => await showDialog<Uri>(
  context: context,
  builder: (context) => SurfaceConfirmationDialog(
    title: const Text('Manage repository access'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final installation in installations)
          TextButton(
            key: ValueKey('github-manage-installation-${installation.id}'),
            onPressed: () => Navigator.pop(context, installation.managementUri),
            child: Text('Manage ${installation.accountLogin}'),
          ),
        TextButton(
          key: const ValueKey('github-install-another-account'),
          onPressed: () => Navigator.pop(context, installUri),
          child: const Text('Install another account'),
        ),
      ],
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
  ),
);

Future<String?> showGitHubCommitDialog(
  BuildContext context, {
  required String repository,
  required String branch,
  required String newPath,
  required bool Function(String) isValidMessage,
}) async {
  final formKey = GlobalKey<FormState>();
  String? submittedValue;
  void submit(BuildContext context) {
    final form = formKey.currentState!;
    if (!form.validate()) return;
    form.save();
    Navigator.pop(context, submittedValue);
  }

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
                      Text('To: $newPath'),
                      const SizedBox(height: 16),
                      const Text('Completed canvas edits are saved before this commit.'),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('github-commit-message'),
                        initialValue: 'docs: save canvas',
                        autofocus: true,
                        maxLength: 72,
                        decoration: const InputDecoration(labelText: 'Commit message'),
                        validator: (value) => isValidMessage(value ?? '')
                            ? null
                            : 'Use a lowercase Conventional Commit subject (72 characters max).',
                        onSaved: (value) => submittedValue = value ?? '',
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
                  TextButton(onPressed: () => submit(context), child: const Text('Commit')),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
