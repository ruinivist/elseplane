// Converts screen-space editor movement to an element's local axes.
// Used by canvas controls when resizing and transforming elements.

import 'dart:math' as math;
import 'dart:ui';

// ---------- Coordinates ----------

Offset screenDeltaToLocal(Offset screenDelta, {required double scale, required double rotation}) {
  final delta = screenDelta / scale;
  final cosine = math.cos(-rotation);
  final sine = math.sin(-rotation);
  return Offset(delta.dx * cosine - delta.dy * sine, delta.dx * sine + delta.dy * cosine);
}
