// Renders the options applied to future pen strokes.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/widgets/stroke_settings.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/discrete_slider.dart';
import 'package:flutter/material.dart';

class PenToolSettings extends StatelessWidget {
  const PenToolSettings({
    required this.color,
    required this.width,
    required this.streamline,
    required this.colorPickerExpanded,
    required this.onColorChanged,
    required this.onColorPickerExpandedChanged,
    required this.onWidthChanged,
    required this.onStreamlineChanged,
    super.key,
  });

  final Color color;
  final double width;
  final double streamline;
  final bool colorPickerExpanded;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<bool> onColorPickerExpandedChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onStreamlineChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      StrokeSettings(
        color: color,
        width: width,
        colorPickerExpanded: colorPickerExpanded,
        onColorChanged: onColorChanged,
        onColorPickerExpandedChanged: onColorPickerExpandedChanged,
        onWidthChanged: onWidthChanged,
      ),
      const SizedBox(height: 10),
      Text('Smoothing', style: BTheme.of(context).typo.label),
      DiscreteSlider(
        key: const ValueKey('pen-smoothing-slider'),
        value: streamline,
        min: penStreamlineMinimum,
        max: penStreamlineMaximum,
        onChanged: onStreamlineChanged,
      ),
    ],
  );
}
