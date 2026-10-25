// Renders the settings panel for the canvas text tool.
// Used by the editor's tool-options overlay for the active text element.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/material.dart';

// ---------- Font options ----------

final List<SelectOption<String>> textFontOptions = [
  for (final fontFamily in textNodeFontFamilies) SelectOption(value: fontFamily, label: fontFamily),
];

// ---------- Settings ----------

/// Presents font, color, and background controls for the active text element.
/// Used by the canvas tool-options overlay during text editing.
class TextToolSettings extends StatefulWidget {
  const TextToolSettings({
    required this.session,
    required this.id,
    required this.onChangeBoundary,
    required this.colorPickerExpanded,
    required this.onColorPickerExpandedChanged,
    this.loadFont = loadTextFont,
    super.key,
  });

  final EditorSession session;
  final String id;
  final VoidCallback onChangeBoundary;
  final bool colorPickerExpanded;
  final ValueChanged<bool> onColorPickerExpandedChanged;

  final Future<void> Function(String) loadFont;

  @override
  State<TextToolSettings> createState() => _TextToolSettingsState();
}

class _TextToolSettingsState extends State<TextToolSettings> {
  bool _loading = false;
  Object? _request;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_modelChanged);
  }

  void _modelChanged() {
    if (widget.session.activeId == widget.id || _request == null) return;
    _request = null;
    setState(() => _loading = false);
  }

  Future<void> _chooseFont(String family) async {
    final session = widget.session;
    final data = session.element(widget.id);
    if (data is! TextElementData) return;
    if (_loading || family == data.style.fontFamily) return;
    final previousFamily = data.style.fontFamily;
    final restoration = session.restorationGeneration;
    final request = Object();
    _request = request;
    setState(() => _loading = true);
    bool ownsRequest() =>
        mounted &&
        session.element(widget.id) is TextElementData &&
        session.isLive &&
        session.restorationGeneration == restoration &&
        session.activeId == widget.id &&
        identical(_request, request) &&
        identical(widget.session, session) &&
        (session.element(widget.id)! as TextElementData).style.fontFamily == previousFamily;
    try {
      await widget.loadFont(family);
      if (!ownsRequest()) return;
      widget.onChangeBoundary();
      session.setTextStyle(
        widget.id,
        (session.element(widget.id)! as TextElementData).style.copyWith(fontFamily: family),
      );
      widget.onChangeBoundary();
    } on Object {
      if (!mounted || !ownsRequest()) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load font')));
    } finally {
      if (mounted && identical(_request, request)) setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant TextToolSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session) || oldWidget.id != widget.id) {
      oldWidget.session.removeListener(_modelChanged);
      widget.session.addListener(_modelChanged);
      _request = null;
      _loading = false;
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_modelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final data = session.element(widget.id);
    if (data is! TextElementData) return const SizedBox.shrink();
    final onChangeBoundary = widget.onChangeBoundary;
    final theme = BTheme.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final current = session.element(widget.id);
        if (current is! TextElementData) return const SizedBox.shrink();
        final style = current.style;
        return Column(
          key: const ValueKey('text-settings-panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Font', style: theme.typo.label),
            const SizedBox(height: 6),
            SearchableSelect<String>(
              key: const ValueKey('text-font-select'),
              value: style.fontFamily,
              options: textNodeFontFamilies.contains(style.fontFamily)
                  ? textFontOptions
                  : [SelectOption(value: style.fontFamily, label: style.fontFamily), ...textFontOptions],
              preferredValues: [style.fontFamily, defaultFontFamily],
              searchHint: 'Search fonts',
              onChanged: _loading ? null : _chooseFont,
            ),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
            const SizedBox(height: 10),
            Text('Color', style: theme.typo.label),
            const SizedBox(height: 6),
            ColorControl(
              color: style.color ?? theme.colors.textPrimary,
              expanded: widget.colorPickerExpanded,
              enableAlpha: false,
              onExpandedChanged: widget.onColorPickerExpandedChanged,
              onChanged: (color) {
                onChangeBoundary();
                session.setTextStyle(
                  widget.id,
                  (session.element(widget.id)! as TextElementData).style.copyWith(color: color),
                );
                onChangeBoundary();
              },
            ),
            const SizedBox(height: 10),
            Text('Background', style: theme.typo.label),
            const SizedBox(height: 6),
            Select<BlockBackgroundKind>(
              key: const ValueKey('text-background-select'),
              value: style.background,
              options: const [
                SelectOption(value: BlockBackgroundKind.transparent, label: 'Transparent'),
                SelectOption(value: BlockBackgroundKind.card, label: 'Card'),
                SelectOption(value: BlockBackgroundKind.glass, label: 'Glass'),
              ],
              onChanged: (background) {
                onChangeBoundary();
                session.setTextStyle(
                  widget.id,
                  (session.element(widget.id)! as TextElementData).style.copyWith(background: background),
                );
                onChangeBoundary();
              },
            ),
          ],
        );
      },
    );
  }
}
