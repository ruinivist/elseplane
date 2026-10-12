// Renders the settings panel for the canvas text tool.
// Used by the editor's tool-options overlay for the active text element.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/tools/text/text_block_model.dart';
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
    required this.model,
    required this.onChangeBoundary,
    required this.colorPickerExpanded,
    required this.onColorPickerExpandedChanged,
    this.loadFont = loadTextFont,
    super.key,
  });

  final TextBlockModel model;
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
    widget.model.addListener(_modelChanged);
  }

  void _modelChanged() {
    if (widget.model.active || _request == null) return;
    _request = null;
    setState(() => _loading = false);
  }

  Future<void> _chooseFont(String family) async {
    final model = widget.model;
    if (_loading || family == model.style.fontFamily) return;
    final previousFamily = model.style.fontFamily;
    final request = Object();
    _request = request;
    setState(() => _loading = true);
    bool ownsRequest() =>
        mounted &&
        !model.disposed &&
        model.active &&
        identical(_request, request) &&
        identical(widget.model, model) &&
        model.style.fontFamily == previousFamily;
    try {
      await widget.loadFont(family);
      if (!ownsRequest()) return;
      widget.onChangeBoundary();
      model.style = model.style.copyWith(fontFamily: family);
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
    if (!identical(oldWidget.model, widget.model)) {
      oldWidget.model.removeListener(_modelChanged);
      widget.model.addListener(_modelChanged);
      _request = null;
      _loading = false;
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_modelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final onChangeBoundary = widget.onChangeBoundary;
    final theme = BTheme.of(context);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final style = model.style;
        final selectedColor = switch (style.color) {
          final color? => colorFromHex(color),
          null => theme.colors.textPrimary,
        };
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
              options: textFontOptions,
              preferredValues: [style.fontFamily, defaultFontFamily],
              searchHint: 'Search fonts',
              onChanged: _loading ? null : _chooseFont,
            ),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
            const SizedBox(height: 10),
            Text('Color', style: theme.typo.label),
            const SizedBox(height: 6),
            ColorControl(
              color: selectedColor,
              expanded: widget.colorPickerExpanded,
              enableAlpha: false,
              onExpandedChanged: widget.onColorPickerExpandedChanged,
              onChanged: (color) {
                onChangeBoundary();
                model.style = style.copyWith(color: colorToHex(color));
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
                model.style = style.copyWith(background: background);
                onChangeBoundary();
              },
            ),
          ],
        );
      },
    );
  }
}

// ---------- Color conversion ----------

String colorToHex(Color color) {
  final value = color.toARGB32() & 0x00ffffff;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color colorFromHex(String value) {
  return Color(int.parse('FF${value.substring(1)}', radix: 16));
}
