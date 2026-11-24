// Renders persisted shapes with movement, resizing, and hit testing.
// Used by the canvas element stack for saved shape models.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_editor_resources.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_kind.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/canvas/geometry/shape_geometry.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/icon_drag.dart';
import 'package:elseplane/ui/common/pointer_scroll_boundary.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

// ---------- Rendering ----------

/// Renders and handles movement and resizing for a persisted shape.
/// Used by the canvas element stack.
class ShapeElementView extends StatefulWidget {
  const ShapeElementView({
    required this.data,
    required this.resources,
    required this.selected,
    required this.active,
    required this.onActivate,
    required this.onMove,
    required this.onResize,
    this.onChangeEnd,
    this.onControlPointerDown,
    super.key,
  });

  final ShapeElementData data;
  final ShapeEditorResources resources;
  final bool selected;
  final bool active;
  final VoidCallback onActivate;
  final ValueChanged<Offset> onMove;
  final VoidCallback? onChangeEnd;
  final PointerDownEventListener? onControlPointerDown;
  final ValueChanged<Offset> onResize;

  @override
  State<ShapeElementView> createState() => _ShapeElementViewState();
}

class _ShapeElementViewState extends State<ShapeElementView> {
  Offset? _dragPosition;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.resources,
      builder: (context, _) {
        final data = widget.resources.data;
        final theme = BTheme.of(context);
        final colors = theme.colors;
        final textBounds = shapeTextBounds(data.kind, data.size, data.strokeWidth);
        final textStyle = theme.typo.body.copyWith(color: data.strokeColor);
        return SizedBox.fromSize(
          size: data.size,
          child: Semantics(
            container: true,
            label: data.kind.label,
            selected: widget.selected,
            child: GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              supportedDevices: const {
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
              },
              onTap: widget.onActivate,
              onPanStart: (details) => _dragPosition = details.globalPosition,
              onPanUpdate: (details) {
                final previous = _dragPosition!;
                _dragPosition = details.globalPosition;
                widget.onMove(details.globalPosition - previous);
              },
              onPanEnd: (_) {
                _dragPosition = null;
                widget.onChangeEnd?.call();
              },
              onPanCancel: () {
                if (_dragPosition == null) return;
                _dragPosition = null;
                widget.onChangeEnd?.call();
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ShapePainter(
                        path: shapePath(data.kind, Offset.zero & data.size),
                        color: widget.selected ? colors.accent : data.strokeColor,
                        fillColor: data.fillColor,
                        strokeWidth: data.strokeWidth,
                      ),
                    ),
                  ),
                  if (widget.resources.editing || !textBounds.isEmpty)
                    Positioned.fromRect(
                      rect: textBounds,
                      child: ClipRect(
                        child: widget.resources.editing
                            ? Focus(
                                onKeyEvent: (_, event) {
                                  if (event is! KeyDownEvent ||
                                      event.logicalKey != LogicalKeyboardKey.enter ||
                                      HardwareKeyboard.instance.isShiftPressed) {
                                    return KeyEventResult.ignored;
                                  }
                                  final composing = widget.resources.controller.value.composing;
                                  if (composing.isValid && !composing.isCollapsed) return KeyEventResult.ignored;
                                  widget.resources.finishEditing();
                                  return KeyEventResult.handled;
                                },
                                child: PointerScrollBoundary(
                                  child: TextField(
                                    key: const ValueKey('shape-text-editor'),
                                    controller: widget.resources.controller,
                                    focusNode: widget.resources.focusNode,
                                    scrollController: widget.resources.scrollController,
                                    contextMenuBuilder: null,
                                    keyboardType: TextInputType.multiline,
                                    expands: true,
                                    maxLines: null,
                                    scrollPadding: EdgeInsets.zero,
                                    textAlign: TextAlign.center,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: textStyle,
                                    cursorColor: colors.accent,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isCollapsed: true,
                                    ),
                                  ),
                                ),
                              )
                            : IgnorePointer(
                                child: Align(
                                  child: Text(
                                    key: const ValueKey('shape-text-preview'),
                                    data.text,
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                    overflow: TextOverflow.clip,
                                    style: textStyle,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  if (widget.active)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: ResizeHandle(
                        key: const ValueKey('shape-resize-handle'),
                        semanticLabel: 'Resize shape',
                        onPointerDown: widget.onControlPointerDown,
                        gestures: {
                          ImmediateMultiDragGestureRecognizer: immediateDragGestureFactory(
                            (_) => CallbackDrag(widget.onResize, onEnd: widget.onChangeEnd),
                          ),
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------- Painter ----------

class _ShapePainter extends CustomPainter {
  const _ShapePainter({
    required this.path,
    required this.color,
    required this.fillColor,
    required this.strokeWidth,
  });

  final Path path;
  final Color color;
  final Color? fillColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    paintShape(
      canvas,
      path: path,
      color: color,
      fillColor: fillColor,
      strokeWidth: strokeWidth,
    );
  }

  @override
  bool hitTest(Offset position) => path.contains(position);

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

// ---------- ShapeElementView painting ----------

void paintShape(
  Canvas canvas, {
  required Path path,
  required Color color,
  required Color? fillColor,
  required double strokeWidth,
}) {
  if (fillColor case final fillColor?) {
    canvas.drawPath(path, Paint()..color = fillColor);
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );
}
