// Computes distances used by canvas ink hit testing.
// Shared by pen and arrow geometry.

import 'dart:ui';

// ---------- Hit testing ----------

double distanceToSegmentSquared(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.distanceSquared;
  if (lengthSquared == 0) return (point - start).distanceSquared;
  final offset = point - start;
  final ratio = ((offset.dx * segment.dx + offset.dy * segment.dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  return (point - (start + segment * ratio)).distanceSquared;
}
