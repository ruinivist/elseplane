// Renders persisted arrows, active editing points, and path-level hit testing.
// Used by the canvas element stack and active arrow editing overlay.

import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/tools/arrow_tool.dart';
import 'package:elseplane/canvas/geometry/arrow_geometry.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ---------- Rendering ----------

/// Renders and exposes semantics for a persisted arrow data.
/// Used by the canvas element stack.
class ArrowElementView extends StatelessWidget {
  const ArrowElementView({required this.data, required this.selected, required this.active, super.key});

  final ArrowElementData data;
  final bool selected;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = BTheme.of(context).colors;
    return SizedBox.fromSize(
      size: data.bounds.size,
      child: Semantics(
        container: true,
        label: 'Arrow',
        selected: selected,
        child: CustomPaint(
          foregroundPainter: _ArrowPainter(
            geometry: data.localGeometry,
            color: selected && !active ? colors.accent : data.color,
            strokeStyle: data.strokeStyle,
            strokeWidth: data.strokeWidth,
          ),
          child: const IgnorePointer(child: SizedBox.expand()),
        ),
      ),
    );
  }
}

/// Draws and handles every editable point of an active arrow.
class ArrowEditor extends StatelessWidget {
  const ArrowEditor({
    required this.data,
    required this.selected,
    required this.active,
    required this.canvasOffset,
    required this.canvasScale,
    required this.onChangeStart,
    required this.onPointChanged,
    required this.onChangeEnd,
    super.key,
  });

  final ArrowElementData data;
  final bool selected;
  final bool active;
  final Offset canvasOffset;
  final double canvasScale;
  final VoidCallback onChangeStart;
  final void Function(int point, Offset position) onPointChanged;
  final VoidCallback onChangeEnd;

  Offset _toScreen(Offset point) => (point - canvasOffset) * canvasScale;

  @override
  Widget build(BuildContext context) {
    final colors = BTheme.of(context).colors;
    final points = [for (var point = 0; point < data.pointCount; point++) _toScreen(data.point(point))];
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('arrow-bezier-guides'),
              painter: _ArrowGuidePainter(
                points: points,
                color: colors.accent.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        for (var point = 0; point < points.length; point++)
          Positioned(
            left: points[point].dx - _ArrowPointHandle.size / 2,
            top: points[point].dy - _ArrowPointHandle.size / 2,
            child: _ArrowPointHandle(
              key: ValueKey(
                'arrow-${point == 0
                    ? 'start'
                    : point == points.length - 1
                    ? 'end'
                    : 'control-${point - 1}'}-handle',
              ),
              label: point == 0
                  ? 'start'
                  : point == points.length - 1
                  ? 'end'
                  : 'control $point',
              isControl: point > 0 && point < points.length - 1,
              position: data.point(point),
              canvasScale: canvasScale,
              onChangeStart: onChangeStart,
              onChanged: (position) => onPointChanged(point, position),
              onChangeEnd: onChangeEnd,
            ),
          ),
      ],
    );
  }
}

class _ArrowPointHandle extends StatefulWidget {
  const _ArrowPointHandle({
    required this.label,
    required this.isControl,
    required this.position,
    required this.canvasScale,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  static const size = 28.0;
  static const visualSize = 10.0;

  final String label;
  final bool isControl;
  final Offset position;
  final double canvasScale;
  final VoidCallback onChangeStart;
  final ValueChanged<Offset> onChanged;
  final VoidCallback onChangeEnd;

  @override
  State<_ArrowPointHandle> createState() => _ArrowPointHandleState();
}

class _ArrowPointHandleState extends State<_ArrowPointHandle> {
  Offset? _requestedPosition;

  @override
  Widget build(BuildContext context) {
    final colors = BTheme.of(context).colors;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: Semantics(
        button: true,
        label: 'Move arrow ${widget.label} point',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) {
            _requestedPosition = widget.position;
            widget.onChangeStart();
          },
          onPanUpdate: (details) {
            final position = _requestedPosition! + details.delta / widget.canvasScale;
            _requestedPosition = position;
            widget.onChanged(position);
          },
          onPanEnd: (_) => _finishDrag(),
          onPanCancel: _finishDrag,
          child: SizedBox.square(
            dimension: _ArrowPointHandle.size,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.isControl ? colors.accent : colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.accent, width: 2),
                ),
                child: const SizedBox.square(dimension: _ArrowPointHandle.visualSize),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _finishDrag() {
    _requestedPosition = null;
    widget.onChangeEnd();
  }
}

class _ArrowGuidePainter extends CustomPainter {
  const _ArrowGuidePainter({
    required this.points,
    required this.color,
  });

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var index = 1; index < points.length; index++) {
      canvas.drawLine(points[index - 1], points[index], paint);
    }
  }

  @override
  bool shouldRepaint(_ArrowGuidePainter oldDelegate) =>
      !listEquals(points, oldDelegate.points) || color != oldDelegate.color;
}

// ---------- Painter ----------

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({
    required this.geometry,
    required this.color,
    required this.strokeStyle,
    required this.strokeWidth,
  });

  final ArrowGeometry geometry;
  final Color color;
  final ArrowStrokeStyle strokeStyle;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    paintArrow(
      canvas,
      geometry: geometry,
      color: color,
      strokeStyle: strokeStyle,
      strokeWidth: strokeWidth,
    );
  }

  @override
  bool hitTest(Offset position) {
    return geometry.hitTest(position, strokeWidth: strokeWidth);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) {
    return oldDelegate.geometry.start != geometry.start ||
        !listEquals(oldDelegate.geometry.controls, geometry.controls) ||
        oldDelegate.geometry.end != geometry.end ||
        oldDelegate.color != color ||
        oldDelegate.strokeStyle != strokeStyle ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

// ---------- ArrowElementView painting ----------

const _arrowDashLength = 8.0;
const _arrowDashGap = 6.0;

void paintArrow(
  Canvas canvas, {
  required ArrowGeometry geometry,
  required Color color,
  required ArrowStrokeStyle strokeStyle,
  required double strokeWidth,
  double dashScale = 1,
}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = strokeWidth;
  canvas
    ..drawPath(
      strokeStyle == ArrowStrokeStyle.dashed
          ? _dashedPath(
              geometry.shaftPath,
              dashLength: _arrowDashLength * dashScale,
              gapLength: _arrowDashGap * dashScale,
            )
          : geometry.shaftPath,
      paint,
    )
    ..drawPath(geometry.arrowheadPath, paint);
}

Path _dashedPath(
  Path source, {
  required double dashLength,
  required double gapLength,
}) {
  final result = Path();
  for (final metric in source.computeMetrics()) {
    for (var distance = 0.0; distance < metric.length; distance += dashLength + gapLength) {
      result.addPath(
        metric.extractPath(distance, math.min(distance + dashLength, metric.length)),
        Offset.zero,
      );
    }
  }
  return result;
}

// Describes and paints an arrow while it is being drawn.
// Used by the arrow tool and the canvas preview overlay.

/// Describes an in-progress arrow before it becomes persisted.
// ---------- Painters ----------

/// Paints an in-progress arrow in screen coordinates.
/// Used by the canvas overlay while [ArrowTool] owns a pointer.
class ArrowPreviewPainter extends CustomPainter {
  const ArrowPreviewPainter({
    required this.preview,
    required this.guideColor,
    required this.canvasOffset,
    required this.canvasScale,
  });

  final ArrowPreview preview;
  final Color guideColor;
  final Offset canvasOffset;
  final double canvasScale;

  @override
  void paint(Canvas canvas, Size size) {
    final screenGeometry = ArrowGeometry(
      start: _toScreen(preview.geometry.start),
      controls: preview.geometry.controls.map(_toScreen).toList(),
      end: _toScreen(preview.geometry.end),
    );
    if (preview.showControls) {
      _ArrowGuidePainter(
        points: [screenGeometry.start, ...screenGeometry.controls, screenGeometry.end],
        color: guideColor.withValues(alpha: 0.55),
      ).paint(canvas, size);
      final paint = Paint()..color = guideColor;
      for (final control in screenGeometry.controls) {
        canvas.drawCircle(control, _ArrowPointHandle.visualSize / 2, paint);
      }
    }
    paintArrow(
      canvas,
      geometry: screenGeometry,
      color: preview.color,
      strokeStyle: preview.strokeStyle,
      strokeWidth: preview.strokeWidth * canvasScale,
      dashScale: canvasScale,
    );
  }

  Offset _toScreen(Offset point) => (point - canvasOffset) * canvasScale;

  @override
  bool shouldRepaint(ArrowPreviewPainter oldDelegate) {
    return oldDelegate.preview.geometry.start != preview.geometry.start ||
        !listEquals(oldDelegate.preview.geometry.controls, preview.geometry.controls) ||
        oldDelegate.preview.geometry.end != preview.geometry.end ||
        oldDelegate.canvasOffset != canvasOffset ||
        oldDelegate.canvasScale != canvasScale ||
        oldDelegate.preview.color != preview.color ||
        oldDelegate.preview.strokeStyle != preview.strokeStyle ||
        oldDelegate.preview.strokeWidth != preview.strokeWidth ||
        oldDelegate.preview.showControls != preview.showControls ||
        oldDelegate.guideColor != guideColor;
  }
}
