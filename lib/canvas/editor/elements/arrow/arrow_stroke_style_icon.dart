// Renders the solid and dashed arrow-style option icons.
// Used by the arrow settings panel.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ---------- Widgets ----------

class ArrowStrokeStyleIcon extends StatelessWidget {
  // ---------- Construction ----------

  const ArrowStrokeStyleIcon({required this.style, super.key});

  final ArrowStrokeStyle style;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final label = style == ArrowStrokeStyle.solid ? 'Solid' : 'Dashed';
    return SvgPicture.asset(
      style == ArrowStrokeStyle.solid ? 'assets/icons/arrow-solid.svg' : 'assets/icons/arrow-dashed.svg',
      width: iconTheme.size ?? BSizes.defaultIconSize,
      height: iconTheme.size ?? BSizes.defaultIconSize,
      colorFilter: ColorFilter.mode(
        iconTheme.color ?? BTheme.of(context).colors.textSecondary,
        BlendMode.srcIn,
      ),
      semanticsLabel: label,
    );
  }
}
