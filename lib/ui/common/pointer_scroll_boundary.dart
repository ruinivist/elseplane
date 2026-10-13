// Provides a boundary that consumes pointer scrolling without blocking drags.
// Used around menus and nested scrollable editors on the infinite canvas.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

// ---------- Widgets ----------

class PointerScrollBoundary extends StatelessWidget {
  // ---------- Construction ----------

  const PointerScrollBoundary({required this.child, super.key});

  final Widget child;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          (event) => (event as PointerScrollEvent).respond(
            allowPlatformDefault: false,
          ),
        );
      },
      child: child,
    );
  }
}
