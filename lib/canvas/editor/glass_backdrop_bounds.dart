// Tests conservative canvas paint bounds in effective back-to-front order.

import 'dart:math' as math;
import 'dart:ui';

typedef GlassBackdropFootprint = ({Rect? bounds, double paintOutset, bool glass});

Set<String> glassCardsWithClearBackdrop(Iterable<MapEntry<String, GlassBackdropFootprint>> backToFront) {
  // Measured starting point; keep filter reach separate from blockers' paint outsets.
  const sampleMargin = 32.0;
  final clear = <String>{};
  final earlier = <Rect>[];
  for (final MapEntry(key: id, value: (:bounds, :paintOutset, :glass)) in backToFront) {
    // Unknown paint can contribute to every subsequent backdrop.
    if (bounds == null || !bounds.isFinite || bounds.isEmpty) break;
    final painted = bounds.inflate(paintOutset);
    if (!painted.isFinite) break;
    if (glass) {
      final sample = bounds.inflate(sampleMargin);
      if (sample.isFinite &&
          !earlier.any(
            (other) =>
                other.left <= sample.right &&
                other.right >= sample.left &&
                other.top <= sample.bottom &&
                other.bottom >= sample.top,
          )) {
        clear.add(id);
      }
    }
    earlier.add(painted);
  }
  return clear;
}

Rect rotatedBackdropBounds(Rect bounds, double rotation) {
  if (rotation == 0) return bounds;
  final cosine = math.cos(rotation);
  final sine = math.sin(rotation);
  final full = Rect.fromCenter(
    center: bounds.center,
    width: bounds.width * cosine.abs() + bounds.height * sine.abs(),
    height: bounds.width * sine.abs() + bounds.height * cosine.abs(),
  );
  // Grid constraints can move the rotation pivot without clipping the child's paint.
  final widthShift = Offset(cosine - 1, sine) * (bounds.width / 2);
  final heightShift = Offset(-sine, cosine - 1) * (bounds.height / 2);
  return full
      .expandToInclude(full.shift(widthShift))
      .expandToInclude(full.shift(heightShift))
      .expandToInclude(full.shift(widthShift + heightShift));
}
