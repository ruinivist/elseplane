// Renders persisted pen strokes and performs stroke-level hit testing.
// Used by the canvas element stack for saved freehand drawings.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_resources.dart';
import 'package:elseplane/canvas/editor/tools/pen_tool.dart';
import 'package:elseplane/canvas/geometry/pen_geometry.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ---------- Rendering ----------

/// Renders and handles movement for a persisted freehand stroke.
/// Used by the canvas element stack.
class PenElementView extends StatefulWidget {
  const PenElementView({
    required this.resources,
    required this.data,
    required this.selected,
    required this.active,
    required this.onMove,
    this.onTap,
    this.onChangeEnd,
    super.key,
  });

  final PenResources resources;
  final PenElementData data;
  final bool selected;
  final bool active;
  final ValueChanged<Offset> onMove;
  final VoidCallback? onChangeEnd;
  final VoidCallback? onTap;

  @override
  State<PenElementView> createState() => _PenElementViewState();
}

class _PenElementViewState extends State<PenElementView> {
  Offset? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final accent = BTheme.of(context).colors.accent;
    return SizedBox.fromSize(
      size: widget.data.size,
      child: ListenableBuilder(
        listenable: widget.resources,
        builder: (context, _) => Semantics(
          container: true,
          label: 'Drawing stroke',
          selected: widget.selected,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onTap: widget.onTap,
            onPanStart: (details) => _dragPosition = details.globalPosition,
            onPanUpdate: (details) {
              final previous = _dragPosition!;
              _dragPosition = details.globalPosition;
              widget.onMove(details.globalPosition - previous);
            },
            onPanEnd: (_) {
              _dragPosition = null;
              widget.onChangeEnd?.call();
            },
            onPanCancel: () {
              if (_dragPosition == null) return;
              _dragPosition = null;
              widget.onChangeEnd?.call();
            },
            child: CustomPaint(
              painter: _PenStrokePainter(
                path: widget.resources.path,
                points: widget.data.points,
                color: widget.data.color,
                width: widget.data.width,
                hitSlop: widget.data.hitSlop,
                selected: widget.selected,
                accent: accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Painter and hit testing ----------

class _PenStrokePainter extends CustomPainter {
  const _PenStrokePainter({
    required this.path,
    required this.points,
    required this.color,
    required this.width,
    required this.hitSlop,
    required this.selected,
    required this.accent,
  });

  final Path path;
  final List<PenPointData> points;
  final Color color;
  final double width;
  final double hitSlop;
  final bool selected;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    if (selected) {
      canvas.drawRect(
        (Offset.zero & size).deflate(1),
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool hitTest(Offset position) {
    return hitTestPenStroke(position, points: points, width: width, hitSlop: hitSlop);
  }

  @override
  bool shouldRepaint(_PenStrokePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.accent != accent;
}
