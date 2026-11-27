import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/geometry/shape_geometry.dart';
import 'package:elseplane/canvas/geometry/transforms.dart';

typedef ArrowSnap = ({ArrowAttachment attachment, Offset position});

/// Resolves attachment sides in the same body frame used by the canvas.
class ArrowAnchorFrame {
  const ArrowAnchorFrame({required this.body, this.rotation = 0, this.shape});

  final Rect body;
  final double rotation;
  final ShapeKind? shape;

  Path? _outline(Rect localBody) {
    final kind = shape;
    return kind == null || kind == ShapeKind.rectangle ? null : shapePath(kind, localBody);
  }

  Offset point(ArrowAnchorSide side) {
    final localBody = Offset.zero & body.size;
    final outline = _outline(localBody);
    if (outline == null) return _rotate(_sidePoint(body, side), rotation);

    final center = localBody.center;
    final edge = _sidePoint(localBody, side);
    final ray = edge - center;
    var localPoint = edge;
    if (!outline.contains(edge)) {
      // All supported shape paths are convex; bisect the center-to-side ray.
      var inside = 0.0;
      var outside = 1.0;
      for (var i = 0; i < 24; i++) {
        final middle = (inside + outside) / 2;
        if (outline.contains(center + ray * middle)) {
          inside = middle;
        } else {
          outside = middle;
        }
      }
      localPoint = center + ray * ((inside + outside) / 2);
    }
    return _rotate(body.topLeft + localPoint, rotation);
  }

  Offset _sidePoint(Rect rect, ArrowAnchorSide side) => switch (side) {
    ArrowAnchorSide.top => rect.topCenter,
    ArrowAnchorSide.right => rect.centerRight,
    ArrowAnchorSide.bottom => rect.bottomCenter,
    ArrowAnchorSide.left => rect.centerLeft,
  };

  bool contains(Offset canvasPosition) {
    final position = _rotate(canvasPosition, -rotation);
    final localBody = Offset.zero & body.size;
    return _outline(localBody)?.contains(position - body.topLeft) ?? body.contains(position);
  }

  Offset _rotate(Offset position, double angle) {
    if (angle == 0) return position;
    final pivot = body.center;
    return pivot + screenDeltaToLocal(position - pivot, scale: 1, rotation: -angle);
  }
}
