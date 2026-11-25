// Owns the themed glass fill, blur, outline, clipping, and shadow.
// Used by app surfaces and independently styled canvas blocks.

import 'dart:ui' as ui;

import 'package:elseplane/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

// ---------- Glass surface ----------

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.selected = false,
    this.blurEnabled = true,
    this.borderRadius,
    this.clipper,
    super.key,
  });

  final Widget child;
  final bool selected;
  final bool blurEnabled;
  final BorderRadius? borderRadius;
  final CustomClipper<Path>? clipper;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final radius = borderRadius ?? theme.geo.radiusLarge;
    final surface = BackdropFilter(
      enabled: blurEnabled,
      filter: ui.ImageFilter.blur(sigmaX: theme.geo.glassBlurSigma, sigmaY: theme.geo.glassBlurSigma),
      child: Material(
        color: theme.colors.glassFill(selected: selected, blurEnabled: blurEnabled),
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
        boxShadow: [theme.geo.glassShadow],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: clipper == null ? surface : ClipPath(clipper: clipper, child: surface),
      ),
    );
  }
}
