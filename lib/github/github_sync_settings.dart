// Presents repository setup and import review for the GitHub workflow.
// Used as the Sync section of the regular Settings dialog.

import 'dart:async';

import 'package:elseplane/github/github_import_dialog.dart';
import 'package:elseplane/github/github_sync.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ---------- Sync settings ----------

class GitHubSyncSettings extends StatefulWidget {
  const GitHubSyncSettings({required this.sync, super.key});

  final GitHubSync sync;

  @override
  State<GitHubSyncSettings> createState() => _GitHubSyncSettingsState();
}

class _GitHubSyncSettingsState extends State<GitHubSyncSettings> {
  var _showInstallations = false;
  var _importDialogOpen = false;
  GitHubSync get _sync => widget.sync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _sync,
    builder: (context, _) {
      final typography = BTheme.of(context).typo;
      final session = _sync.session;
      final disabled = _sync.busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _octicon(context, 'mark-github'),
              const SizedBox(width: 8),
              Text('GitHub', style: typography.label),
            ],
          ),
          const SizedBox(height: 8),
          if (session.account case final account?) ...[
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Connected as @${account.login}'),
                TextButton(
                  key: const ValueKey('github-logout'),
                  onPressed: disabled ? null : _sync.logout,
                  child: const Text('Log out'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _repositoryControls(context),
            const SizedBox(height: 12),
            _importControls(),
          ] else if (session.logoutNeedsRetry)
            TextButton(
              key: const ValueKey('github-logout-retry'),
              onPressed: disabled ? null : _sync.logout,
              child: const Text('Retry logout'),
            )
          else if (!session.busy || _sync.progress != null)
            FilledButton(
              key: const ValueKey('github-connect'),
              onPressed: disabled ? null : _sync.connect,
              child: const Text('Connect GitHub'),
            ),
          if (session.error case final error?) _status(error),
          if (session.discoveryError case final error?) _status(error),
          if (_sync.message case final message? when message != session.error) _status(message),
          if (!_importDialogOpen && (_sync.progress != null || session.busy)) ...[
            const SizedBox(height: 8),
            _status(
              _sync.progress ?? (session.discoveryLoading ? 'Checking repository access…' : 'Checking GitHub session…'),
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      );
    },
  );

  // ---------- Repository setup ----------

  Widget _repositoryControls(BuildContext context) {
    final session = _sync.session;
    final saved = _sync.destination;
    final repository = _sync.repository;
    final disabled = _sync.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _octicon(context, 'repo'),
            const SizedBox(width: 8),
            Text('Repository', style: BTheme.of(context).typo.label),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: 'GitHub repository',
                child: SearchableSelect<int?>(
                  key: const ValueKey('github-repository-select'),
                  value: repository != null && repository.defaultBranch == saved?.branch ? repository.id : null,
                  placeholder: saved != null && repository == null
                      ? '${saved.owner}/${saved.repository}'
                      : 'Choose repository',
                  options: [
                    for (final repo in session.repositories) SelectOption(value: repo.id, label: repo.fullName),
                  ],
                  searchHint: 'Search repositories',
                  onChanged: disabled || !_sync.canSelect || session.repositories.isEmpty
                      ? null
                      : (id) {
                          if (id != null) unawaited(_sync.selectRepository(id));
                        },
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('github-refresh-repositories'),
              tooltip: 'Refresh repositories',
              onPressed: disabled ? null : _sync.refreshRepositories,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (repository != null)
          _status('${repository.isPrivate ? 'Private' : 'Public'} · Default branch: ${repository.defaultBranch}'),
        if (_sync.repositoryStatus case final status?) _status(status),
      ],
    );
  }

  Widget _importControls() {
    final disabled = _sync.busy;
    final installations = _sync.session.installations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('github-import'),
              onPressed: (disabled && !_sync.commitInProgress) || !_sync.canImport
                  ? null
                  : () => unawaited(_openImportDialog()),
              child: const Text('Import from GitHub'),
            ),
            TextButton(
              key: const ValueKey('github-manage-access'),
              onPressed: disabled
                  ? null
                  : installations.isEmpty
                  ? () => _sync.manageAccess(_sync.installUri)
                  : () => setState(() => _showInstallations = !_showInstallations),
              child: const Text('Manage GitHub access'),
            ),
          ],
        ),
        if (_showInstallations && installations.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final installation in installations)
                TextButton(
                  key: ValueKey('github-manage-installation-${installation.id}'),
                  onPressed: disabled ? null : () => _sync.manageAccess(installation.managementUri),
                  child: Text('Manage ${installation.accountLogin}'),
                ),
              TextButton(
                onPressed: disabled ? null : () => _sync.manageAccess(_sync.installUri),
                child: const Text('Install another account'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _openImportDialog() async {
    final attempt = _sync.startImport();
    if (attempt == null) return;
    setState(() => _importDialogOpen = true);
    try {
      await showGitHubImportDialog(context, sync: _sync, attempt: attempt);
    } finally {
      _sync.closeImport(attempt);
      if (mounted) setState(() => _importDialogOpen = false);
    }
  }

  Widget _status(String message) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Semantics(
      liveRegion: true,
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    ),
  );

  Widget _octicon(BuildContext context, String name) => SvgPicture.asset(
    'assets/icons/octicons/$name-16.svg',
    width: 16,
    height: 16,
    colorFilter: ColorFilter.mode(BTheme.of(context).colors.textPrimary, BlendMode.srcIn),
  );
}
