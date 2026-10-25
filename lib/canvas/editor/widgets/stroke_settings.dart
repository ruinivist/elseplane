// Shares color and width controls between pen and arrow settings.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:flutter/material.dart';

class StrokeSettings extends StatelessWidget {
  const StrokeSettings({
    required this.color,
    required this.width,
    required this.colorPickerExpanded,
    required this.onColorChanged,
    required this.onColorPickerExpandedChanged,
    required this.onWidthChanged,
    this.widthMinimum = 0.25,
    this.widthMaximum = 5.0,
    this.widthLabelOffset = 0,
    super.key,
  });

  final Color color;
  final double width;
  final double widthMinimum;
  final double widthMaximum;
  final int widthLabelOffset;
  final bool colorPickerExpanded;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<bool> onColorPickerExpandedChanged;
  final ValueChanged<double> onWidthChanged;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Color', style: theme.typo.label),
        const SizedBox(height: 6),
        ColorControl(
          color: color,
          expanded: colorPickerExpanded,
          onChanged: onColorChanged,
          onExpandedChanged: onColorPickerExpandedChanged,
        ),
        const SizedBox(height: 10),
        Text('Width', style: theme.typo.label),
        DiscreteSlider(
          key: const ValueKey('stroke-width-slider'),
          value: width,
          min: widthMinimum,
          max: widthMaximum,
          labelOffset: widthLabelOffset,
          onChanged: onWidthChanged,
        ),
      ],
    );
  }
}
