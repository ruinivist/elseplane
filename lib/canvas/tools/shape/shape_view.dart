// Renders persisted shapes with movement, resizing, and hit testing.
// Used by the canvas element stack for saved shape models.

part of 'shape_tool.dart';

// ---------- Rendering ----------

/// Renders and handles movement and resizing for a persisted shape.
/// Used by the canvas element stack.
class Shape extends StatefulWidget {
  const Shape({
    required this.model,
    required this.onActivate,
    required this.onMove,
    required this.onResize,
    super.key,
  });

  final ShapeModel model;
  final VoidCallback onActivate;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;

  @override
  State<Shape> createState() => _ShapeState();
}

class _ShapeState extends State<Shape> {
  Offset? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final colors = BTheme.of(context).colors;
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) => SizedBox.fromSize(
        size: widget.model.canvasSize,
        child: Semantics(
          container: true,
          label: widget.model.data.kind.label,
          selected: widget.model.selected,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onTap: widget.onActivate,
            onPanStart: (details) => _dragPosition = details.globalPosition,
            onPanUpdate: (details) {
              final previous = _dragPosition!;
              _dragPosition = details.globalPosition;
              widget.onMove(details.globalPosition - previous);
            },
            onPanEnd: (_) => _dragPosition = null,
            onPanCancel: () => _dragPosition = null,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ShapePainter(
                      path: shapePath(
                        widget.model.data.kind,
                        Offset.zero & widget.model.canvasSize,
                      ),
                      color: widget.model.selected ? colors.accent : widget.model.data.strokeColor,
                      fillColor: widget.model.data.fillColor,
                      strokeWidth: widget.model.data.strokeWidth,
                    ),
                  ),
                ),
                if (widget.model.active)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: ResizeHandle(
                      key: const ValueKey('shape-resize-handle'),
                      semanticLabel: 'Resize shape',
                      gestures: {
                        ImmediateMultiDragGestureRecognizer: immediateDragGestureFactory(
                          (_) => CallbackDrag(widget.onResize),
                        ),
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Painter ----------

class _ShapePainter extends CustomPainter {
  const _ShapePainter({
    required this.path,
    required this.color,
    required this.fillColor,
    required this.strokeWidth,
  });

  final Path path;
  final Color color;
  final Color? fillColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    paintShape(
      canvas,
      path: path,
      color: color,
      fillColor: fillColor,
      strokeWidth: strokeWidth,
    );
  }

  @override
  bool hitTest(Offset position) => path.contains(position);

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

// ---------- Shape painting ----------

void paintShape(
  Canvas canvas, {
  required Path path,
  required Color color,
  required Color? fillColor,
  required double strokeWidth,
}) {
  if (fillColor case final fillColor?) {
    canvas.drawPath(path, Paint()..color = fillColor);
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );
}

// ---------- Labels ----------

/// Maps persisted shape kinds to concise user-facing labels.
/// Used by shape semantics and tool option controls.
extension ShapeKindLabel on ShapeKind {
  String get label => switch (this) {
    ShapeKind.rectangle => 'Rectangle',
    ShapeKind.roundedRectangle => 'Rounded rectangle',
    ShapeKind.ellipse => 'Ellipse',
    ShapeKind.diamond => 'Diamond',
    ShapeKind.triangle => 'Triangle',
    ShapeKind.hexagon => 'Hexagon',
  };
}
