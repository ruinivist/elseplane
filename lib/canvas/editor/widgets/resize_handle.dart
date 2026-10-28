// Provides the themed drag handle shown on resizable canvas elements.
// Used by text, code, media, and shape element controls.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/resize_icon.dart';
import 'package:flutter/material.dart';

// ---------- Widgets ----------

class ResizeHandle extends StatelessWidget {
  // ---------- Construction ----------

  const ResizeHandle({
    required this.semanticLabel,
    required this.gestures,
    this.showCornerSurface = false,
    this.onPointerDown,
    super.key,
  });

  final String semanticLabel;
  final Map<Type, GestureRecognizerFactory> gestures;
  final bool showCornerSurface;
  final PointerDownEventListener? onPointerDown;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: Listener(
          onPointerDown: onPointerDown,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: gestures,
            child: showCornerSurface
                ? SizedBox.square(
                    dimension: 22,
                    child: CustomPaint(
                      painter: _CornerSurfacePainter(BTheme.of(context).colors.surface),
                      child: const Align(
                        alignment: Alignment.bottomRight,
                        child: ResizeIcon(),
                      ),
                    ),
                  )
                : const ResizeIcon(),
          ),
        ),
      ),
    );
  }
}

class _CornerSurfacePainter extends CustomPainter {
  const _CornerSurfacePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CornerSurfacePainter oldDelegate) => color != oldDelegate.color;
}
