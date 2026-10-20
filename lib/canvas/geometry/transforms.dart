// Converts editor deltas and tests transformed selection bounds.
// Used after the editor obtains viewport and measured element geometry.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

// ---------- Coordinates ----------

Offset screenDeltaToLocal(Offset screenDelta, {required double scale, required double rotation}) {
  final delta = screenDelta / scale;
  final cosine = math.cos(-rotation);
  final sine = math.sin(-rotation);
  return Offset(delta.dx * cosine - delta.dy * sine, delta.dx * sine + delta.dy * cosine);
}

// ---------- Selection ----------

bool transformedRectOverlaps(Rect selection, Size size, Float64List transform) {
  final elementPath = (Path()..addRect(Offset.zero & size)).transform(transform);
  final overlap = Path.combine(PathOperation.intersect, Path()..addRect(selection), elementPath).getBounds();
  return !overlap.isEmpty;
}
