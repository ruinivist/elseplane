// Collects and validates the commit message for the current canvas.
// Opened by the GitHub workflow before publishing the captured canvas.

import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/material.dart';

// ---------- Commit dialog ----------

Future<String?> showGitHubCommitDialog(
  BuildContext context, {
  required String repository,
  required String branch,
  required String newPath,
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
                        validator: (value) => isValidGitHubCommitMessage(value ?? '')
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
