// Provides a transparent native menu shell and one bounded themed surface.
// Used by selects, context menus, and their native submenus.

import 'dart:math' as math;

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

// ---------- Menu content ----------

class MenuSurface extends StatelessWidget {
  const MenuSurface({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return PointerScrollBoundary(
      child: Surface(
        kind: SurfaceKind.menu,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(0, media.size.height - media.padding.vertical - media.viewInsets.bottom - 48),
          ),
          child: AnimatedPrimaryScrollController(
            child: SingleChildScrollView(
              primary: true,
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
