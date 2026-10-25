// Renders creation and active-element options for arrows.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_stroke_style_icon.dart';
import 'package:elseplane/canvas/editor/widgets/stroke_settings.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';

class ArrowToolSettings extends StatelessWidget {
  const ArrowToolSettings({
    required this.color,
    required this.strokeStyle,
    required this.strokeWidth,
    required this.colorPickerExpanded,
    required this.onColorChanged,
    required this.onStrokeStyleChanged,
    required this.onStrokeWidthChanged,
    required this.onColorPickerExpandedChanged,
    super.key,
  });

  final Color color;
  final ArrowStrokeStyle strokeStyle;
  final double strokeWidth;
  final bool colorPickerExpanded;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<ArrowStrokeStyle> onStrokeStyleChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<bool> onColorPickerExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Style', style: theme.typo.label),
        const SizedBox(height: 6),
        Wrap(
          children: [
            for (final option in ArrowStrokeStyle.values)
              Tooltip(
                message: option == ArrowStrokeStyle.solid ? 'Solid' : 'Dashed',
                child: ToolbarButton(
                  key: ValueKey('arrow-style-${option.name}'),
                  selected: option == strokeStyle,
                  onPressed: () => onStrokeStyleChanged(option),
                  child: ArrowStrokeStyleIcon(style: option),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        StrokeSettings(
          color: color,
          width: strokeWidth,
          widthMinimum: arrowStrokeWidthMinimum,
          widthMaximum: arrowStrokeWidthMaximum,
          widthLabelOffset: -3,
          colorPickerExpanded: colorPickerExpanded,
          onColorChanged: onColorChanged,
          onColorPickerExpandedChanged: onColorPickerExpandedChanged,
          onWidthChanged: onStrokeWidthChanged,
        ),
      ],
    );
  }
}
