// Provides elseplane's themed surface container.
// Used by canvas editors, floating controls, and tool option panels.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:flutter/material.dart';

// ---------- Widgets ----------

enum SurfaceKind { panel, menu, dialog }

class Surface extends StatelessWidget {
  // ---------- Construction ----------

  const Surface({
    required this.child,
    this.selected = false,
    this.raised = true,
    this.kind = SurfaceKind.panel,
    super.key,
  });

  final Widget child;
  final bool selected;
  final bool raised;
  final SurfaceKind kind;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final radius = kind == SurfaceKind.menu ? theme.geo.radiusMedium : theme.geo.radiusLarge;
    if (theme.surfaceStyle == SurfaceStyle.glass) {
      return GlassSurface(selected: selected, borderRadius: radius, child: child);
    }
    return Material(
      color: selected
          ? colors.accentSoft
          : raised
          ? colors.surfaceRaised
          : colors.surface,
      elevation: selected
          ? 0
          : kind == SurfaceKind.panel
          ? theme.geo.elevationLow
          : theme.geo.elevationMedium,
      shadowColor: colors.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected ? BorderSide(color: colors.accent, width: 2) : BorderSide(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
