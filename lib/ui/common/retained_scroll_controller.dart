// Retains animated scroll offsets while lazy views detach and remount.
// Used by canvas text and code resources across viewport culling.

import 'package:flutter/widgets.dart';
import 'package:scroll_animator/scroll_animator.dart';

// ---------- Scroll lifetime ----------

class RetainedScrollController extends AnimatedScrollController {
  RetainedScrollController() : super(animationFactory: const ChromiumEaseInOut(), keepScrollOffset: false);

  double _offset = 0;

  @override
  double get initialScrollOffset => _offset;

  @override
  void detach(ScrollPosition position) {
    if (position.hasPixels) _offset = position.pixels;
    super.detach(position);
  }
}
