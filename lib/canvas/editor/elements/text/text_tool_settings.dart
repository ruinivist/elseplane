// Renders the settings panel for the canvas text tool.
// Used by the editor's tool-options overlay for the active text element.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_font_controls.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:material_ui/material_ui.dart';

// ---------- Settings ----------

/// Presents typography, color, and background controls for the active text element.
/// Used by the canvas tool-options overlay during text editing.
class TextToolSettings extends StatelessWidget {
  const TextToolSettings({
    required this.session,
    required this.id,
    required this.onChangeBoundary,
    required this.colorPickerExpanded,
    required this.onColorPickerExpandedChanged,
    this.onLegacyPointerDown,
    this.onSizeChosen,
    this.loadFont = loadTextFont,
    super.key,
  });

  final EditorSession session;
  final String id;
  final VoidCallback onChangeBoundary;
  final bool colorPickerExpanded;
  final ValueChanged<bool> onColorPickerExpandedChanged;
  final VoidCallback? onLegacyPointerDown;
  final VoidCallback? onSizeChosen;
  final Future<void> Function(String) loadFont;

  void _editStyle(TextNodeStyle Function(TextNodeStyle) edit, {bool keepEditing = false}) {
    final data = session.element(id);
    if (!session.isLive || session.activeId != id || data is! TextElementData) return;
    if (!keepEditing && session.editing == (id: id, field: EditorField.markdown)) session.editField(null);
    final next = edit(data.style);
    if (next == data.style) return;
    onChangeBoundary();
    session.setTextStyle(id, next);
    onChangeBoundary();
  }

  Widget _legacyGroup(List<Widget> children) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => onLegacyPointerDown?.call(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final current = session.element(id);
        if (current is! TextElementData) return const SizedBox.shrink();
        final style = current.style;
        return Column(
          key: const ValueKey('text-settings-panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _legacyGroup([
              Text('Font', style: theme.typo.label),
              const SizedBox(height: 6),
              CanvasFontSelect(
                session: session,
                id: id,
                selectKey: const ValueKey('text-font-select'),
                loadFont: loadFont,
                readFamily: (value) => value is TextElementData ? value.style.fontFamily : null,
                onChosen: onLegacyPointerDown,
                onLoaded: (family) => _editStyle((style) => style.copyWith(fontFamily: family), keepEditing: true),
              ),
            ]),
            const SizedBox(height: 10),
            TextFieldTapRegion(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Font size', style: theme.typo.label),
                  const SizedBox(height: 6),
                  CanvasFontSizeSelect(
                    key: const ValueKey('text-font-size-select'),
                    value: style.fontSize ?? defaultTextFontSize,
                    onChanged: (size) {
                      _editStyle(
                        (style) =>
                            (style.fontSize ?? defaultTextFontSize) == size ? style : style.copyWith(fontSize: size),
                        keepEditing: true,
                      );
                      onSizeChosen?.call();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _legacyGroup([
              Text('Color', style: theme.typo.label),
              const SizedBox(height: 6),
              ColorControl(
                color: style.color ?? theme.colors.textPrimary,
                expanded: colorPickerExpanded,
                enableAlpha: false,
                onExpandedChanged: onColorPickerExpandedChanged,
                onChanged: (color) => _editStyle((style) => style.copyWith(color: color)),
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
                onChanged: (background) => _editStyle((style) => style.copyWith(background: background)),
              ),
            ]),
          ],
        );
      },
    );
  }
}
