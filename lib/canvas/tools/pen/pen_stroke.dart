// Renders persisted pen strokes and performs stroke-level hit testing.
// Used by the canvas element stack for saved freehand drawings.

part of 'pen_tool.dart';

// ---------- Rendering ----------

/// Renders and handles movement for a persisted freehand stroke.
/// Used by the canvas element stack.
class PenStroke extends StatefulWidget {
  const PenStroke({
    required this.model,
    required this.onMove,
    this.onTap,
    super.key,
  });

  final PenStrokeModel model;
  final ValueChanged<Offset> onMove;
  final VoidCallback? onTap;

  @override
  State<PenStroke> createState() => _PenStrokeState();
}

class _PenStrokeState extends State<PenStroke> {
  Offset? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final accent = BTheme.of(context).colors.accent;
    return SizedBox.fromSize(
      size: widget.model.canvasSize,
      child: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) => Semantics(
          container: true,
          label: 'Drawing stroke',
          selected: widget.model.selected,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onTap: widget.onTap,
            onPanStart: (details) => _dragPosition = details.globalPosition,
            onPanUpdate: (details) {
              final previous = _dragPosition!;
              _dragPosition = details.globalPosition;
              widget.onMove(details.globalPosition - previous);
            },
            onPanEnd: (_) => _dragPosition = null,
            onPanCancel: () => _dragPosition = null,
            child: CustomPaint(
              painter: _PenStrokePainter(
                path: widget.model.path,
                points: widget.model.data.points,
                color: Color(widget.model.data.color),
                width: widget.model.data.width,
                hitSlop: widget.model.data.hitSlop,
                selected: widget.model.selected,
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
    final radiusSquared = (width + hitSlop) * (width + hitSlop);
    if (points.length == 1) {
      return (position - points.single.position).distanceSquared <= radiusSquared;
    }
    for (var index = 1; index < points.length; index++) {
      if (distanceToSegmentSquared(
            position,
            points[index - 1].position,
            points[index].position,
          ) <=
          radiusSquared) {
        return true;
      }
    }
    return false;
  }

  @override
  bool shouldRepaint(_PenStrokePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.accent != accent;
}
