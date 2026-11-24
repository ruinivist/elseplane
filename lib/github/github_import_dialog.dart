// Presents the cancellable and saving phases of a GitHub repository import.

import 'package:elseplane/github/github_sync.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Future<void> showGitHubImportDialog(
  BuildContext context, {
  required GitHubSync sync,
  required GitHubImport attempt,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _GitHubImportDialog(sync: sync, attempt: attempt),
  );
}

class _GitHubImportDialog extends StatelessWidget {
  const _GitHubImportDialog({required this.sync, required this.attempt});

  final GitHubSync sync;
  final GitHubImport attempt;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) {
      final theme = BTheme.of(context);
      final phase = attempt.phase;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => _dismiss(context),
        },
        child: Focus(
          // Keep dialog shortcuts active without focusing an action.
          autofocus: true,
          skipTraversal: true,
          child: PopScope<void>(
            canPop: phase != GitHubImportPhase.saving,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) sync.closeImport(attempt);
            },
            child: SurfaceDialog(
              key: const ValueKey('github-import-dialog'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          24,
                          24,
                          phase == GitHubImportPhase.saving ? 24 : 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    namesRoute: true,
                                    child: Text('Import from GitHub', style: theme.typo.title),
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('github-import-close'),
                                  tooltip: 'Close',
                                  onPressed: phase == GitHubImportPhase.saving ? null : () => _dismiss(context),
                                  style: BSizes.compactIconButtonStyle,
                                  icon: const Icon(LucideIcons.x),
                                ),
                              ],
                            ),
                            if (phase != GitHubImportPhase.result) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${attempt.destination.owner}/${attempt.destination.repository} · '
                                '${attempt.destination.branch}',
                                style: theme.typo.body,
                              ),
                            ],
                            const SizedBox(height: 16),
                            _phaseContent(theme, phase),
                          ],
                        ),
                      ),
                    ),
                    if (phase != GitHubImportPhase.saving)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: OverflowBar(
                          alignment: MainAxisAlignment.end,
                          spacing: 8,
                          children: _actions(context, phase),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _phaseContent(BTheme theme, GitHubImportPhase phase) => switch (phase) {
    GitHubImportPhase.preparing => _progress(theme, 'Preparing import…'),
    GitHubImportPhase.confirm => _confirmation(theme),
    GitHubImportPhase.saving => _progress(theme, 'Saving canvases…'),
    GitHubImportPhase.result => Semantics(
      liveRegion: true,
      child: Text(attempt.result ?? 'Import could not be completed.', style: theme.typo.body),
    ),
  };

  Widget _progress(BTheme theme, String message) => Row(
    children: [
      ExcludeSemantics(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.colors.textPrimary),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Text(message, style: theme.typo.body),
        ),
      ),
    ],
  );

  Widget _confirmation(BTheme theme) {
    final paths = attempt.overwritePaths.toList()..sort();
    final count = attempt.canvasCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$count ${count == 1 ? 'canvas' : 'canvases'} ready to import.', style: theme.typo.body),
        if (paths.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Will replace ${paths.length} local ${paths.length == 1 ? 'canvas' : 'canvases'}:',
            style: theme.typo.body,
          ),
          const SizedBox(height: 8),
          for (final path in paths) Text(path, style: theme.typo.body),
          const SizedBox(height: 8),
          Text('Shared images may also change in other canvases.', style: theme.typo.body),
        ],
      ],
    );
  }

  List<Widget> _actions(BuildContext context, GitHubImportPhase phase) => switch (phase) {
    GitHubImportPhase.preparing || GitHubImportPhase.confirm => [
      TextButton(
        key: const ValueKey('github-import-cancel'),
        onPressed: () => _dismiss(context),
        child: const Text('Cancel'),
      ),
      if (phase == GitHubImportPhase.confirm)
        FilledButton(
          onPressed: () {
            if (attempt.phase == GitHubImportPhase.confirm) sync.confirmImport(attempt);
          },
          child: const Text('Import canvases'),
        ),
    ],
    GitHubImportPhase.saving => const [],
    GitHubImportPhase.result => [
      TextButton(onPressed: () => _dismiss(context), child: const Text('Done')),
    ],
  };

  void _dismiss(BuildContext context) {
    if (attempt.phase == GitHubImportPhase.saving || ModalRoute.of(context)?.isCurrent != true) return;
    sync.closeImport(attempt);
    if (context.mounted) Navigator.of(context).pop();
  }
}
