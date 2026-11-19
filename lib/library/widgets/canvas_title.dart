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
    super.key,
  });

  final List<String> path;
  final VoidCallback? onPressed;
  final String? indicator;
  final String? indicatorLabel;
  final String? actionLabel;
  final VoidCallback? onAction;

  // ---------- Sizing ----------

  static const _horizontalPadding = 12.0;
  static const _indicatorWidth = 40.0;
  static const _minimumNameWidth = 32.0;
  static const _actionPadding = 32.0;

  /// Reserves room for the name and any title action before placing the toolbar.
  double collapsedWidthOf(BuildContext context) =>
      _textWidth(context, path.last, _textStyleOf(context)) +
      (indicator == null
          ? _horizontalPadding * 2
          : _horizontalPadding +
                _indicatorWidth +
                (actionLabel == null
                    ? 0
                    : _actionPadding + _textWidth(context, actionLabel!, Theme.of(context).textTheme.labelLarge)));

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
    final path = widget.path.join(' / ');
    final name = Semantics(
      label: path,
      button: widget.onPressed != null,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: theme.geo.radiusSmall,
        child: Padding(
          padding: const EdgeInsets.only(left: CanvasTitle._horizontalPadding),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(widget.path.last, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
    return Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.deferToChild,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          height: _height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final actionWidth = math.max<double>(
                0,
                constraints.maxWidth - CanvasTitle._indicatorWidth - CanvasTitle._minimumNameWidth,
              );
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Tooltip(message: path, child: name),
                  ),
                  Tooltip(
                    message: widget.indicatorLabel ?? widget.indicator!,
                    child: InkWell(
                      key: const ValueKey('canvas-title-indicator'),
                      borderRadius: theme.geo.radiusSmall,
                      onTap: widget.onAction,
                      child: SizedBox(
                        width: math.min(CanvasTitle._indicatorWidth, constraints.maxWidth),
                        height: _height,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(widget.indicator!, style: textStyle, semanticsLabel: ''),
                        ),
                      ),
                    ),
                  ),
                  if (widget.actionLabel case final label?)
                    Visibility(
                      visible: _hovered || _focused,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: actionWidth),
                        child: TextButton(
                          key: const ValueKey('canvas-title-action'),
                          style: actionWidth < 80
                              ? TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4))
                              : null,
                          onPressed: actionWidth == 0 ? null : widget.onAction,
                          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
