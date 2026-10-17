// Provides a transparent native menu shell and one bounded themed surface.
// Used by selects, context menus, and their native submenus.

import 'dart:math' as math;

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/pointer_scroll_boundary.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/material.dart';
import 'package:scroll_animator/scroll_animator.dart';

// ---------- Native shell ----------

MenuStyle menuShellStyle({double Function()? width, AlignmentGeometry? alignment}) => MenuStyle(
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(0),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  minimumSize: const WidgetStatePropertyAll(Size.zero),
  fixedSize: width == null ? null : WidgetStateProperty.resolveWith((_) => Size.fromWidth(width())),
  maximumSize: const WidgetStatePropertyAll(Size.infinite),
  visualDensity: VisualDensity.standard,
  side: const WidgetStatePropertyAll(BorderSide.none),
  shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
  alignment: alignment,
);

// ---------- Menu items ----------

ButtonStyle menuItemStyle(BTheme theme, {required bool destructive}) {
  final colors = theme.colors;
  final foreground = destructive ? colors.destructive : colors.textPrimary;
  return MenuItemButton.styleFrom(
    foregroundColor: colors.textMuted,
    disabledForegroundColor: colors.textMuted,
    iconColor: foreground,
    disabledIconColor: colors.textMuted,
    backgroundColor: Colors.transparent,
    disabledBackgroundColor: Colors.transparent,
    textStyle: theme.typo.body,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    minimumSize: const Size(0, 34),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    alignment: Alignment.centerLeft,
    shape: RoundedRectangleBorder(borderRadius: theme.geo.radiusSmall),
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) return colors.surfacePressed;
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return colors.surfaceHover;
      }
      return Colors.transparent;
    }),
  );
}

// ---------- Menu content ----------

class MenuSurface extends StatelessWidget {
  const MenuSurface({required this.children, this.scrollable = true, super.key});

  final List<Widget> children;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return PointerScrollBoundary(
      child: Surface(
        kind: SurfaceKind.menu,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(0, media.size.height - media.padding.vertical - media.viewInsets.bottom - 48),
          ),
          child: scrollable
              ? AnimatedPrimaryScrollController(
                  child: SingleChildScrollView(
                    primary: true,
                    padding: const EdgeInsets.all(4),
                    child: content,
                  ),
                )
              : Padding(padding: const EdgeInsets.all(4), child: content),
        ),
      ),
    );
  }
}
