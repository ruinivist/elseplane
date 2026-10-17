// Provides the canvas name with a hover-revealed breadcrumb path.
// Used by the canvas editor UI and its isolated component preview.

import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';

// ---------- Canvas title ----------

class CanvasTitle extends StatefulWidget {
  // ---------- Construction ----------

  const CanvasTitle({required this.path, this.onPressed, super.key});

  final List<String> path;
  final VoidCallback? onPressed;

  // ---------- Sizing ----------

  static const _horizontalPadding = 12.0;

  /// Measures the name and padding without the hover-revealed folder path.
  double collapsedWidthOf(BuildContext context) =>
      TextPainter.computeWidth(
        text: TextSpan(
          text: path.last,
          style: DefaultTextStyle.of(context).style
              .merge(_textStyleOf(context))
              .copyWith(
                fontWeight: MediaQuery.boldTextOf(context) ? FontWeight.bold : null,
                letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
                wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
              ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      ) +
      _horizontalPadding * 2;

  static TextStyle _textStyleOf(BuildContext context) {
    final theme = BTheme.of(context);
    return theme.typo.body.copyWith(color: theme.colors.textPrimary, fontSize: 14);
  }

  @override
  State<CanvasTitle> createState() => _CanvasTitleState();
}

class _CanvasTitleState extends State<CanvasTitle> {
  // ---------- Constants ----------

  static const _animationDuration = Duration(milliseconds: 150);
  static const _height = 40.0;

  // ---------- State ----------

  var _hovered = false;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final textStyle = CanvasTitle._textStyleOf(context);

    return Semantics(
      label: widget.path.join(' / '),
      button: widget.onPressed != null,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: theme.geo.radiusSmall,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            height: _height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: CanvasTitle._horizontalPadding),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.path.length > 1)
                  TweenAnimationBuilder<double>(
                    duration: _animationDuration,
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0, end: _hovered ? 1 : 0),
                    child: Text(
                      '${widget.path.take(widget.path.length - 1).join(' / ')} / ',
                      style: textStyle,
                    ),
                    builder: (context, value, child) => ClipRect(
                      child: Align(
                        alignment: Alignment.centerRight,
                        widthFactor: value,
                        child: Opacity(opacity: value, child: child),
                      ),
                    ),
                  ),
                Text(widget.path.last, style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
