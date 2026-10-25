// Provides the canvas toolbar's button styles and sizing.
// Used by toolbar actions and tool option buttons.

import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';

// ---------- Widgets ----------

class ToolbarButton extends StatelessWidget {
  // ---------- Construction ----------

  const ToolbarButton({
    required this.onPressed,
    required this.child,
    required this.selected,
    this.compact = true,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool selected;
  final bool compact;

  // ---------- Geometry ----------

  static const _regularMinimumSize = Size(88, 48);

  /// Returns the regular icon button size after Flutter's density adjustment.
  /// Used by the toolbar to choose spacing before its buttons are laid out.
  static Size regularSizeOf(BuildContext context) {
    final theme = Theme.of(context);
    final density = theme.textButtonTheme.style?.visualDensity ?? theme.visualDensity;
    return density
        .effectiveConstraints(
          BoxConstraints(
            minWidth: _regularMinimumSize.width,
            minHeight: _regularMinimumSize.height,
          ),
        )
        .smallest;
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? theme.colors.textMuted
                : selected
                ? theme.colors.accent
                : theme.colors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.isEmpty && selected) return theme.colors.surfacePressed;
            return null;
          }),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: WidgetStatePropertyAll(
            compact ? Size.zero : _regularMinimumSize,
          ),
          fixedSize: compact ? const WidgetStatePropertyAll(BSizes.defaultIconButtonSize) : null,
        ),
        child: IconTheme.merge(
          data: const IconThemeData(size: BSizes.defaultIconSize),
          child: child,
        ),
      ),
    );
  }
}
