// Provides the animated surface that hosts active tool options.
// Used by the canvas toolbar when switching editing tools.

import 'package:elseplane/ui/common/pointer_scroll_boundary.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/material.dart';
import 'package:scroll_animator/scroll_animator.dart';

// ---------- Widgets ----------

class ToolOptions extends StatelessWidget {
  // ---------- Construction ----------

  const ToolOptions({required this.child, super.key});

  final Widget? child;

  // ---------- Geometry ----------

  static const _padding = 12.0;
  static const contentWidth = 160.0;
  static const double outerWidth = contentWidth + _padding * 2;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topRight,
        clipBehavior: Clip.none,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Surface(
              child: PointerScrollBoundary(
                child: AnimatedPrimaryScrollController(
                  child: SingleChildScrollView(
                    primary: true,
                    padding: const EdgeInsets.all(_padding),
                    child: SizedBox(width: contentWidth, child: child),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
