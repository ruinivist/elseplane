// Owns the themed glass fill, blur, outline, clipping, and shadow.
// Used by app surfaces and independently styled canvas blocks.

import 'dart:ui' as ui;

import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';

// ---------- Glass surface ----------

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.selected = false,
    this.borderRadius,
    this.clipper,
    super.key,
  });

  final Widget child;
  final bool selected;
  final BorderRadius? borderRadius;
  final CustomClipper<Path>? clipper;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final radius = borderRadius ?? theme.geo.radiusLarge;
    final surface = BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: theme.geo.glassBlurSigma, sigmaY: theme.geo.glassBlurSigma),
      child: Material(
        color: selected
            ? Color.alphaBlend(theme.colors.accentSoft.withValues(alpha: 0.25), theme.colors.glassSurface)
            : theme.colors.glassSurface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? BorderSide(color: theme.colors.accent, width: 2)
              : BorderSide(color: theme.colors.glassBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [theme.geo.glassShadow.copyWith(color: theme.colors.shadow)],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: clipper == null ? surface : ClipPath(clipper: clipper, child: surface),
      ),
    );
  }
}
