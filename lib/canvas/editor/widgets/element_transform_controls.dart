// Renders shared movement, rotation, arrangement, and deletion controls for canvas elements.
// Used by the canvas overlay for active elements.

import 'dart:math' as math;

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/icon_drag.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ---------- Controls ----------

class ElementTransformControls extends StatelessWidget {
  const ElementTransformControls({
    required this.elementName,
    required this.rotation,
    required this.onMove,
    required this.onDelete,
    required this.onArrange,
    required this.onTransformStart,
    required this.onTransformEnd,
    required this.rotationCenter,
    this.onRotate,
    this.tapRegionGroupId,
    super.key,
  });

  final String elementName;
  final double rotation;
  final ValueChanged<Offset> onMove;
  final ValueChanged<double>? onRotate;
  final VoidCallback onDelete;
  final ValueChanged<Rect> onArrange;
  final VoidCallback onTransformStart;
  final VoidCallback onTransformEnd;
  final ValueGetter<Offset> rotationCenter;
  final Object? tapRegionGroupId;

  static final size = Size(BSizes.defaultIconButtonSize.width, BSizes.defaultIconButtonSize.height * 4);

  @override
  Widget build(BuildContext context) {
    final controls = SizedBox(
      width: size.width,
      height: size.height,
      child: TextFieldTapRegion(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconDrag(
              key: ValueKey('$elementName-block-handle'),
              semanticLabel: 'Move $elementName block',
              onDragStart: (_) {
                onTransformStart();
                return _ElementDrag(onMove, onTransformEnd);
              },
              icon: const Icon(Icons.drag_indicator, size: 20),
            ),
            if (onRotate case final onRotate?)
              IconDrag(
                key: ValueKey('$elementName-block-rotate-control'),
                semanticLabel: 'Rotate $elementName block',
                onDragStart: (position) {
                  onTransformStart();
                  return _ElementRotateDrag(
                    startPosition: position,
                    center: rotationCenter(),
                    rotation: rotation,
                    onRotate: onRotate,
                    onEnd: onTransformEnd,
                  );
                },
                icon: const Icon(Icons.rotate_right, size: 20),
              ),
            Tooltip(
              message: 'Arrange',
              child: Builder(
                builder: (context) => MouseRegion(
                  key: ValueKey('$elementName-block-arrange-control'),
                  cursor: SystemMouseCursors.click,
                  child: Semantics(
                    button: true,
                    label: 'Arrange $elementName block',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final box = context.findRenderObject()! as RenderBox;
                        onArrange(MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size));
                      },
                      child: SizedBox.fromSize(
                        size: BSizes.defaultIconButtonSize,
                        child: Icon(LucideIcons.layers, size: 20, color: BTheme.of(context).colors.textSecondary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Delete',
              child: MouseRegion(
                key: ValueKey('$elementName-block-delete-control'),
                cursor: SystemMouseCursors.click,
                child: Semantics(
                  button: true,
                  label: 'Delete $elementName block',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDelete,
                    child: SizedBox.fromSize(
                      size: BSizes.defaultIconButtonSize,
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: BTheme.of(context).colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final groupId = tapRegionGroupId;
    return groupId == null ? controls : TapRegion(groupId: groupId, child: controls);
  }
}

// ---------- Gestures ----------

class _ElementDrag extends Drag {
  _ElementDrag(this.onMove, this.onEnd);

  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;

  @override
  void update(DragUpdateDetails details) => onMove(details.delta);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onEnd();
}

class _ElementRotateDrag extends Drag {
  _ElementRotateDrag({
    required Offset startPosition,
    required this.center,
    required this._rotation,
    required this.onRotate,
    required this.onEnd,
  }) : _lastPointerAngle = _pointerAngle(startPosition, center);

  final Offset center;
  final ValueChanged<double> onRotate;
  final VoidCallback onEnd;
  double _lastPointerAngle;
  double _rotation;

  @override
  void update(DragUpdateDetails details) {
    final pointerAngle = _pointerAngle(details.globalPosition, center);
    var delta = pointerAngle - _lastPointerAngle;
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta < -math.pi) delta += math.pi * 2;
    _rotation += delta;
    _lastPointerAngle = pointerAngle;
    onRotate(_rotation);
  }

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onEnd();
}

double _pointerAngle(Offset pointer, Offset center) => math.atan2(pointer.dy - center.dy, pointer.dx - center.dx);
