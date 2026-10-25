// Renders persisted shapes with movement, resizing, and hit testing.
// Used by the canvas element stack for saved shape models.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/tools/shape_tool.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/canvas/geometry/shape_geometry.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/icon_drag.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ---------- Rendering ----------

/// Renders and handles movement and resizing for a persisted shape.
/// Used by the canvas element stack.
class ShapeElementView extends StatefulWidget {
  const ShapeElementView({
    required this.data,
    required this.selected,
    required this.active,
    required this.onActivate,
    required this.onMove,
    required this.onResize,
    this.onChangeEnd,
    super.key,
  });

  final ShapeElementData data;
  final bool selected;
  final bool active;
  final VoidCallback onActivate;
  final ValueChanged<Offset> onMove;
  final VoidCallback? onChangeEnd;
  final ValueChanged<Offset> onResize;

  @override
  State<ShapeElementView> createState() => _ShapeElementViewState();
}

class _ShapeElementViewState extends State<ShapeElementView> {
  Offset? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final colors = BTheme.of(context).colors;
    return SizedBox.fromSize(
      size: widget.data.size,
      child: Semantics(
        container: true,
        label: widget.data.kind.label,
        selected: widget.selected,
        child: GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onTap: widget.onActivate,
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
            _dragPosition = null;
            widget.onChangeEnd?.call();
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ShapePainter(
                    path: shapePath(
                      widget.data.kind,
                      Offset.zero & widget.data.size,
                    ),
                    color: widget.selected ? colors.accent : widget.data.strokeColor,
                    fillColor: widget.data.fillColor,
                    strokeWidth: widget.data.strokeWidth,
                  ),
                ),
              ),
              if (widget.active)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: ResizeHandle(
                    key: const ValueKey('shape-resize-handle'),
                    semanticLabel: 'Resize shape',
                    gestures: {
                      ImmediateMultiDragGestureRecognizer: immediateDragGestureFactory(
                        (_) => CallbackDrag(widget.onResize, onEnd: widget.onChangeEnd),
                      ),
                    },
                  ),
                ),
            ],
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

// ---------- ShapeElementView painting ----------

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
