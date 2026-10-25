// Renders creation and active-element options for shapes.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_kind.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  @override
  Widget build(BuildContext context) {
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
