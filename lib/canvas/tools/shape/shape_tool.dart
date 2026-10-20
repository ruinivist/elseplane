// Provides shape geometry, creation state, rendering, and interaction.
// Used by the canvas shape tool and persisted shape elements.

import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/widgets/resize_handle.dart';
import 'package:elseplane/canvas/geometry/shape_geometry.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/icon_drag.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

export 'package:elseplane/canvas/geometry/shape_geometry.dart';

part 'shape_model.dart';
part 'shape_preview.dart';
part 'shape_view.dart';

// ---------- Tool state ----------

/// Tracks shape options and pointer input while creating shapes.
/// Used by the canvas page to produce [ShapeModel] instances.
class ShapeTool extends ChangeNotifier {
  // ---------- Construction ----------

  ShapeTool({required this.onShape});

  final ValueChanged<ShapeModel> onShape;
  final _uuid = const Uuid();
  ShapeKind _kind = ShapeKind.roundedRectangle;
  Color _strokeColor = defaultCanvasColor;
  Color? _fillColor;
  double _strokeWidth = 2;
  int? _pointer;
  Offset? _start;
  Offset? _end;

  // ---------- Options and preview ----------

  ShapeKind get kind => _kind;
  Color get strokeColor => _strokeColor;
  Color? get fillColor => _fillColor;
  double get strokeWidth => _strokeWidth;

  ShapePreview? get preview {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return null;
    return ShapePreview(
      kind: _kind,
      rect: Rect.fromPoints(start, end),
      strokeColor: _strokeColor,
      fillColor: _fillColor,
      strokeWidth: _strokeWidth,
    );
  }

  void setKind(ShapeKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    notifyListeners();
  }

  void setStrokeColor(Color color) {
    if (_strokeColor == color) return;
    _strokeColor = color;
    notifyListeners();
  }

  void setFillColor(Color? color) {
    if (_fillColor == color) return;
    _fillColor = color;
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    if (_strokeWidth == width) return;
    _strokeWidth = width;
    notifyListeners();
  }

  // ---------- Pointer events ----------

  bool ownsPointer(int pointer) => _pointer == pointer;

  void onPointerDown(PointerDownEvent event, Offset canvasPosition) {
    if (event.buttons != kPrimaryButton || _pointer != null) return;
    _pointer = event.pointer;
    _start = canvasPosition;
    _end = canvasPosition;
    notifyListeners();
  }

  void onPointerMove(PointerMoveEvent event, Offset canvasPosition) {
    if (!ownsPointer(event.pointer)) return;
    _end = canvasPosition;
    notifyListeners();
  }

  void onPointerUp(PointerUpEvent event, Offset canvasPosition) {
    if (!ownsPointer(event.pointer)) return;
    _end = canvasPosition;
    final preview = this.preview;
    _clearPreview();
    if (preview == null ||
        preview.rect.width < shapeMinimumSize.width ||
        preview.rect.height < shapeMinimumSize.height) {
      return;
    }
    onShape(
      ShapeModel(
        ShapeElementData(
          id: _uuid.v4(),
          kind: preview.kind,
          position: preview.rect.topLeft,
          size: preview.rect.size,
          strokeColor: preview.strokeColor,
          fillColor: preview.fillColor,
          strokeWidth: preview.strokeWidth,
        ),
      ),
    );
  }

  void onPointerCancel(PointerCancelEvent event) {
    if (ownsPointer(event.pointer)) _clearPreview();
  }

  void cancel() {
    if (_pointer != null) _clearPreview();
  }

  // ---------- Private helpers ----------

  void _clearPreview() {
    _pointer = null;
    _start = null;
    _end = null;
    notifyListeners();
  }
}
