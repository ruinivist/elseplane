// Provides the canvas name, breadcrumb path, and optional title action.
// Used by the canvas editor UI and its isolated component preview.

import 'dart:math' as math;

import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';

// ---------- Canvas title ----------

class CanvasTitle extends StatefulWidget {
  // ---------- Construction ----------

  const CanvasTitle({
    required this.path,
    this.onPressed,
    this.indicator,
    this.indicatorLabel,
    this.actionLabel,
    this.onAction,
    this.showActionWithoutHover = false,
    super.key,
  });

  final List<String> path;
  final VoidCallback? onPressed;
  final String? indicator;
  final String? indicatorLabel;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showActionWithoutHover;

  // ---------- Sizing ----------

  static const _horizontalPadding = 12.0;

  /// Measures the title used to place it beside the toolbar.
  double collapsedWidthOf(BuildContext context) {
    final style = _textStyleOf(context);
    return _textWidth(context, path.last, style) +
        _horizontalPadding * 2 +
        (indicator == null ? 0 : _textWidth(context, indicator!, style));
  }

  static double _textWidth(BuildContext context, String text, TextStyle? style) => TextPainter.computeWidth(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style
          .merge(style)
          .copyWith(
            fontWeight: MediaQuery.boldTextOf(context) ? FontWeight.bold : null,
            letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
            wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
          ),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  );

  static TextStyle _textStyleOf(BuildContext context) {
    final theme = BTheme.of(context);
    return theme.typo.body.copyWith(color: theme.colors.textPrimary);
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
  var _focused = false;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final textStyle = CanvasTitle._textStyleOf(context);

    if (widget.indicator != null) return _titleWithAction(theme, textStyle);

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

  Widget _titleWithAction(BTheme theme, TextStyle textStyle) {
    final showAction = _hovered || _focused || (widget.showActionWithoutHover && widget.onAction != null);
    return Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.translucent,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final controls = Wrap(
              children: [
                _markedTitle(theme, textStyle, constraints.maxWidth),
                if (showAction && widget.actionLabel != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: _height),
                    child: TextButton(
                      key: const ValueKey('canvas-title-action'),
                      style: constraints.maxWidth < 80
                          ? TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6))
                          : null,
                      onPressed: widget.onAction,
                      child: Text(widget.actionLabel!),
                    ),
                  ),
              ],
            );
            if (widget.collapsedWidthOf(context) <= constraints.maxWidth) return controls;
            return Tooltip(
              message: widget.path.join(' / '),
              excludeFromSemantics: true,
              positionDelegate: (position) => positionDependentBox(
                size: position.overlaySize,
                childSize: position.tooltipSize,
                target: position.target,
                preferBelow: true,
                verticalOffset: position.targetSize.height / 2 + 4,
              ),
              child: controls,
            );
          },
        ),
      ),
    );
  }

  Widget _markedTitle(BTheme theme, TextStyle textStyle, double maxWidth) {
    final path = widget.path.join(' / ');
    final indicatorLabel = widget.indicatorLabel;
    const padding = EdgeInsets.symmetric(horizontal: CanvasTitle._horizontalPadding);

    return Semantics(
      label: indicatorLabel == null ? path : '$path, $indicatorLabel',
      button: widget.onPressed != null,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: theme.geo.radiusSmall,
        child: SizedBox(
          height: _height,
          child: Padding(
            padding: padding,
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.path.last,
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  LimitedBox(
                    maxWidth: math.max(0, maxWidth - padding.horizontal),
                    child: Text(widget.indicator!, style: textStyle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
