// Provides elseplane's draggable icon control.
// Used by canvas controls that start pointer transformations.

import 'package:elseplane/theme/sizes.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ---------- Gestures ----------

GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer> immediateDragGestureFactory(
  GestureMultiDragStartCallback onStart,
) {
  return GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
    ImmediateMultiDragGestureRecognizer.new,
    (recognizer) => recognizer.onStart = onStart,
  );
}

class CallbackDrag extends Drag {
  CallbackDrag(this.onUpdate, {this.onEnd});

  final ValueChanged<Offset> onUpdate;
  final VoidCallback? onEnd;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.delta);
  @override
  void end(DragEndDetails details) => onEnd?.call();
  @override
  void cancel() => onEnd?.call();
}

// ---------- Widgets ----------

class IconDrag extends StatelessWidget {
  // ---------- Construction ----------

  const IconDrag({
    required this.icon,
    required this.semanticLabel,
    required this.onDragStart,
    super.key,
  });

  final Widget icon;
  final String semanticLabel;
  final GestureMultiDragStartCallback onDragStart;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            ImmediateMultiDragGestureRecognizer: immediateDragGestureFactory(onDragStart),
          },
          child: SizedBox.square(
            dimension: BSizes.defaultIconButtonSize.width,
            child: Center(
              child: IconTheme.merge(
                data: const IconThemeData(size: BSizes.defaultIconSize),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
