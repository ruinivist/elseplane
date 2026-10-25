// Renders options for the active code element.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/labeled_switch.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/material.dart';

/// Presents line-number and background settings for the active code block.
class CodeToolSettings extends StatelessWidget {
  const CodeToolSettings({
    required this.session,
    required this.id,
    required this.onChangeBoundary,
    super.key,
  });

  final EditorSession session;
  final String id;
  CodeElementData get data => session.element(id)! as CodeElementData;
  final VoidCallback onChangeBoundary;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.element(id) is! CodeElementData) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledSwitch(
              key: const ValueKey('code-show-line-numbers'),
              label: 'Line numbers',
              value: data.showLineNumbers,
              onChanged: _setShowLineNumbers,
            ),
            const SizedBox(height: 10),
            Text('Background', style: theme.typo.label),
            const SizedBox(height: 6),
            Select<BlockBackgroundKind>(
              key: const ValueKey('code-background-select'),
              value: data.background,
              options: const [
                SelectOption(value: BlockBackgroundKind.transparent, label: 'Transparent'),
                SelectOption(value: BlockBackgroundKind.card, label: 'Card'),
                SelectOption(value: BlockBackgroundKind.glass, label: 'Glass'),
              ],
              onChanged: (background) {
                onChangeBoundary();
                session.setCodeBackground(id, background);
                onChangeBoundary();
              },
            ),
          ],
        );
      },
    );
  }

  void _setShowLineNumbers(bool value) {
    onChangeBoundary();
    session.setLineNumbers(id, value: value);
    onChangeBoundary();
  }
}
