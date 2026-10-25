// Describes and paints a shape while it is being drawn.
// Used by the shape tool and the canvas preview overlay.

import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:elseplane/canvas/editor/tools/shape_tool.dart';
import 'package:flutter/material.dart';

// ---------- Preview model ----------

/// Describes an in-progress shape before it becomes a persisted model.
/// Produced by [ShapeTool] and consumed by the canvas preview painter.
// ---------- Painters ----------

/// Paints an in-progress shape in screen coordinates.
/// Used by the canvas overlay while [ShapeTool] owns a pointer.
class ShapePreviewPainter extends CustomPainter {
  const ShapePreviewPainter({
    required this.preview,
    required this.canvasOffset,
    required this.canvasScale,
  });

  final ShapePreview preview;
  final Offset canvasOffset;
  final double canvasScale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(
      (preview.rect.topLeft - canvasOffset) * canvasScale,
      (preview.rect.bottomRight - canvasOffset) * canvasScale,
    );
    final path = shapePath(preview.kind, rect);
    paintShape(
      canvas,
      path: path,
      color: preview.strokeColor,
      fillColor: preview.fillColor,
      strokeWidth: preview.strokeWidth * canvasScale,
    );
  }

  @override
  bool shouldRepaint(ShapePreviewPainter oldDelegate) =>
      oldDelegate.preview.kind != preview.kind ||
      oldDelegate.preview.rect != preview.rect ||
      oldDelegate.canvasOffset != canvasOffset ||
      oldDelegate.canvasScale != canvasScale ||
      oldDelegate.preview.strokeColor != preview.strokeColor ||
      oldDelegate.preview.fillColor != preview.fillColor ||
      oldDelegate.preview.strokeWidth != preview.strokeWidth;
}
