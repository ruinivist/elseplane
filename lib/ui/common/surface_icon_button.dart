// Provides elseplane's pressable icon control.
// Used by canvas controls that expose a click action.

import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/material.dart';

// ---------- Widgets ----------

class SurfaceIconButton extends StatelessWidget {
  // ---------- Construction ----------

  const SurfaceIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) => Surface(
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
    ),
  );
}
