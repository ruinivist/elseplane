// Renders creation and active-element options for shapes.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_kind.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_font_controls.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class ShapeToolSettings extends StatelessWidget {
  const ShapeToolSettings({
    required this.kind,
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
    required this.outlineColorPickerExpanded,
    required this.fillColorPickerExpanded,
    required this.onKindChanged,
    required this.onStrokeColorChanged,
    required this.onFillColorChanged,
    required this.onStrokeWidthChanged,
    required this.onOutlineColorPickerExpandedChanged,
    required this.onFillColorPickerExpandedChanged,
    this.onDrawingPointerDown,
    this.labelOptions,
    super.key,
  });

  final ShapeKind kind;
  final Color strokeColor;
  final Color? fillColor;
  final double strokeWidth;
  final bool outlineColorPickerExpanded;
  final bool fillColorPickerExpanded;
  final ValueChanged<ShapeKind> onKindChanged;
  final ValueChanged<Color> onStrokeColorChanged;
  final ValueChanged<Color?> onFillColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<bool> onOutlineColorPickerExpandedChanged;
  final ValueChanged<bool> onFillColorPickerExpandedChanged;
  final VoidCallback? onDrawingPointerDown;
  final Widget? labelOptions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => onDrawingPointerDown?.call(),
        child: _drawingOptions(context),
      ),
      ?labelOptions,
    ],
  );

  Widget _drawingOptions(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Shape', style: theme.typo.label),
        const SizedBox(height: 6),
        Wrap(
          children: [
            for (final option in ShapeKind.values)
              Tooltip(
                message: option.label,
                child: ToolbarButton(
                  key: ValueKey('shape-option-${option.name}'),
                  selected: option == kind,
                  onPressed: () => onKindChanged(option),
                  child: Icon(
                    option.icon,
                    semanticLabel: option.label,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Outline', style: theme.typo.label),
        const SizedBox(height: 6),
        ColorControl(
          key: const ValueKey('shape-outline-color'),
          color: strokeColor,
          expanded: outlineColorPickerExpanded,
          onChanged: onStrokeColorChanged,
          onExpandedChanged: onOutlineColorPickerExpandedChanged,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Text('Fill', style: theme.typo.label)),
            Semantics(
              selected: fillColor == null,
              child: IconButton(
                key: const ValueKey('shape-fill-none'),
                tooltip: 'No fill',
                constraints: BoxConstraints.tight(BSizes.colorButtonSize),
                iconSize: BSizes.defaultIconSize,
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const CircleBorder(),
                  side: BorderSide(
                    color: fillColor == null ? theme.colors.focusRing : Colors.transparent,
                    width: 2,
                  ),
                ),
                onPressed: () => onFillColorChanged(null),
                icon: const Icon(LucideIcons.ban),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ColorControl(
          key: const ValueKey('shape-fill-color'),
          color: fillColor,
          expanded: fillColorPickerExpanded,
          onChanged: onFillColorChanged,
          onExpandedChanged: onFillColorPickerExpandedChanged,
        ),
        const SizedBox(height: 10),
        Text('Width', style: theme.typo.label),
        DiscreteSlider(
          value: strokeWidth,
          onChanged: onStrokeWidthChanged,
        ),
      ],
    );
  }
}

class ShapeLabelSettings extends StatelessWidget {
  const ShapeLabelSettings({
    required this.session,
    required this.id,
    required this.colorPickerExpanded,
    required this.onColorPickerExpandedChanged,
    this.onDropdownChosen,
    this.onError,
    this.loadFont = loadTextFont,
    super.key,
  });

  final EditorSession session;
  final String id;
  final bool colorPickerExpanded;
  final ValueChanged<bool> onColorPickerExpandedChanged;
  final VoidCallback? onDropdownChosen;
  final ValueChanged<String>? onError;
  final Future<void> Function(String) loadFont;

  ShapeElementData? _labeledShape(CanvasElementData? value) =>
      value is ShapeElementData && value.text.trim().isNotEmpty ? value : null;

  void _edit({double? size, String? family, Color? color, bool clearColor = false}) {
    final shape = _labeledShape(session.element(id));
    if (!session.isLive || session.activeId != id || shape == null) return;
    if ((size == null || size == (shape.labelFontSize ?? defaultShapeLabelFontSize)) &&
        (family == null || family == (shape.labelFontFamily ?? defaultFontFamily)) &&
        (clearColor ? shape.labelColor == null : color == null || color == shape.labelColor)) {
      return;
    }
    session
      ..finishOperation()
      ..setShapeLabelStyle(id, fontSize: size, fontFamily: family, color: color, clearColor: clearColor)
      ..finishOperation();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final shape = _labeledShape(session.element(id));
      if (shape == null) return const SizedBox.shrink();
      final label = BTheme.of(context).typo.label;
      return TextFieldTapRegion(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text('Font', style: label),
            const SizedBox(height: 6),
            CanvasFontSelect(
              session: session,
              id: id,
              loadFont: loadFont,
              selectKey: const ValueKey('shape-label-font-select'),
              readFamily: (value) {
                final current = _labeledShape(value);
                return current == null ? null : current.labelFontFamily ?? defaultFontFamily;
              },
              onChosen: onDropdownChosen,
              onError: onError,
              onLoaded: (family) => _edit(family: family),
            ),
            const SizedBox(height: 10),
            Text('Font size', style: label),
            const SizedBox(height: 6),
            CanvasFontSizeSelect(
              key: const ValueKey('shape-label-size-select'),
              value: shape.labelFontSize ?? defaultShapeLabelFontSize,
              onChanged: (size) {
                _edit(size: size);
                onDropdownChosen?.call();
              },
            ),
            const SizedBox(height: 10),
            Text('Text color', style: label),
            const SizedBox(height: 6),
            ColorControl(
              key: const ValueKey('shape-label-color'),
              color: shape.labelColor ?? shape.strokeColor,
              expanded: colorPickerExpanded,
              onExpandedChanged: onColorPickerExpandedChanged,
              onChanged: (color) => _edit(color: color),
            ),
            if (shape.labelColor != null)
              TextButton(onPressed: () => _edit(clearColor: true), child: const Text('Use outline color')),
          ],
        ),
      );
    },
  );
}
