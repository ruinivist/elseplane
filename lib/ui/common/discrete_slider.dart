// Provides the themed discrete slider used for bounded numeric choices.
// Used by canvas tool settings that edit stepped values.

import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';

// ---------- Geometry ----------

const _defaultMinimum = 0.25;
const _defaultMaximum = 5.0;
const _defaultStepSize = 0.25;
const _trackHeight = 4.0;
const _thumbDiameter = 16.0;

// ---------- Widgets ----------

/// Renders the stepped slider used for bounded numeric choices.
/// Used by tool settings that expose stepped numeric values.
class DiscreteSlider extends StatelessWidget {
  // ---------- Construction ----------

  const DiscreteSlider({
    required this.value,
    required this.onChanged,
    this.min = _defaultMinimum,
    this.max = _defaultMaximum,
    this.stepSize = _defaultStepSize,
    this.labelOffset = 0,
    super.key,
  }) : assert(min < max, 'min must be less than max'),
       assert(stepSize > 0, 'stepSize must be greater than 0'),
       assert(
         value >= min && value <= max,
         'value must be between min and max',
       );

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final double stepSize;
  final int labelOffset;

  int get divisions => ((max - min) / stepSize).round();

  String _label(double value) => '${(value / stepSize).round() + labelOffset}';

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final labelStyle = theme.typo.label.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1,
    );

    return SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: colors.accent,
            inactiveTrackColor: colors.surfacePressed,
            disabledActiveTrackColor: colors.accent.withValues(alpha: 0.38),
            disabledInactiveTrackColor: colors.surfaceSubtle,
            trackHeight: _trackHeight,
            trackShape: const RoundedRectSliderTrackShape(),
            thumbColor: colors.surfaceRaised,
            disabledThumbColor: colors.surfaceSubtle,
            thumbShape: _DiscreteSliderThumbShape(colors),
            overlayShape: SliderComponentShape.noOverlay,
            overlayColor: Colors.transparent,
            tickMarkShape: SliderTickMarkShape.noTickMark,
            valueIndicatorShape: _DiscreteSliderValueIndicatorShape(
              accentColor: colors.accent,
              backgroundColor: colors.surfaceRaised,
              borderColor: colors.borderSubtle,
              textStyle: labelStyle,
            ),
            valueIndicatorColor: colors.surfaceRaised,
            valueIndicatorTextStyle: labelStyle,
            showValueIndicator: ShowValueIndicator.onDrag,
          ),
          child: Slider(
            key: const ValueKey('discrete-slider'),
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: _label(value),
            semanticFormatterCallback: _label,
            onChanged: onChanged == null ? null : (next) => onChanged!(next.clamp(min, max)),
          ),
        ),
      ),
    );
  }
}

// ---------- Slider shapes ----------

class _DiscreteSliderThumbShape extends SliderComponentShape {
  const _DiscreteSliderThumbShape(this.colors);

  final BColors colors;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size.square(_thumbDiameter);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final thumbPath = Path()
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: _thumbDiameter / 2,
        ),
      );
    canvas.drawShadow(thumbPath, colors.shadow, 2, true);

    final thumbColor = Color.lerp(
      colors.surfaceSubtle,
      Color.lerp(
        colors.surfaceRaised,
        colors.surface,
        activationAnimation.value,
      ),
      enableAnimation.value,
    );
    canvas
      ..drawCircle(
        center,
        _thumbDiameter / 2,
        Paint()..color = thumbColor!,
      )
      ..drawCircle(
        center,
        _thumbDiameter / 2 - 0.5,
        Paint()
          ..color = colors.borderSubtle
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }
}

class _DiscreteSliderValueIndicatorShape extends SliderComponentShape {
  const _DiscreteSliderValueIndicatorShape({
    required this.accentColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.textStyle,
  });

  final Color accentColor;
  final Color backgroundColor;
  final Color borderColor;
  final TextStyle textStyle;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(48, 24);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final progress = activationAnimation.value.clamp(0.0, 1.0);
    final scale = 0.94 + progress * 0.06;
    final label = labelPainter.text?.toPlainText() ?? '';
    final numberPainter = _textPainter(
      label,
      accentColor,
      textDirection,
      textScaleFactor,
      progress,
    );
    const horizontalPadding = 9.0;
    const pillHeight = 24.0;
    const pillGap = 8.0;
    final pillWidth = numberPainter.width + horizontalPadding * 2;
    final bounds = sizeWithOverflow.isEmpty ? parentBox.size : sizeWithOverflow;
    final left = (center.dx - pillWidth / 2).clamp(
      0.0,
      (bounds.width - pillWidth).clamp(0.0, double.infinity),
    );
    final pillRect = Rect.fromLTWH(
      left,
      center.dy - pillHeight - pillGap,
      pillWidth,
      pillHeight,
    );
    final path = Path()..addRRect(RRect.fromRectAndRadius(pillRect, const Radius.circular(7)));
    final canvas = context.canvas;
    final drawPath = canvas.drawPath;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale, scale)
      ..translate(-center.dx, -center.dy);
    drawPath(
      path,
      Paint()..color = backgroundColor.withValues(alpha: progress),
    );
    drawPath(
      path,
      Paint()
        ..color = borderColor.withValues(alpha: progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final textTop = pillRect.top + (pillHeight - numberPainter.height) / 2;
    numberPainter.paint(
      canvas,
      Offset(pillRect.left + horizontalPadding, textTop),
    );
    canvas.restore();
  }

  TextPainter _textPainter(
    String text,
    Color color,
    TextDirection textDirection,
    double textScaleFactor,
    double opacity,
  ) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(color: color.withValues(alpha: opacity)),
      ),
      textDirection: textDirection,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
  }
}
