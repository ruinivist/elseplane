// Provides arrow geometry, editing state, rendering, and hit testing.
// Used by the canvas arrow creation and selection flows.

import 'dart:math' as math;

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

part 'arrow_geometry.dart';
part 'arrow_model.dart';
part 'arrow_preview.dart';
part 'arrow_view.dart';

// ---------- Tool state ----------

/// Tracks pointer input while creating arrows on the canvas.
/// Used by the canvas page to produce [ArrowModel] instances.
class ArrowTool extends ChangeNotifier {
  // ---------- Construction ----------

  ArrowTool({required this.onArrow});

  final ValueChanged<ArrowModel> onArrow;
  final _uuid = const Uuid();
  int? _pointer;
  String? _id;
  Offset? _start;
  Offset? _end;
  final _controls = <Offset>[];
  int _buttons = 0;
  Color _color = defaultCanvasColor;
  ArrowStrokeStyle _strokeStyle = ArrowStrokeStyle.solid;
  double _strokeWidth = 2;

  // ---------- Options and preview ----------

  bool get isDrawing => _pointer != null;
  Color get color => _color;
  ArrowStrokeStyle get strokeStyle => _strokeStyle;
  double get strokeWidth => _strokeWidth;

  ArrowPreview? get preview {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return null;
    return (
      geometry: ArrowGeometry(
        start: start,
        controls: _curveControls(start, end),
        end: end,
      ),
      color: _color,
      strokeStyle: _strokeStyle,
      strokeWidth: _strokeWidth,
      showControls: _controls.isNotEmpty,
    );
  }

  void setColor(Color color) {
    if (_color == color) return;
    _color = color;
    notifyListeners();
  }

  void setStrokeStyle(ArrowStrokeStyle strokeStyle) {
    if (_strokeStyle == strokeStyle) return;
    _strokeStyle = strokeStyle;
    notifyListeners();
  }

  void setStrokeWidth(double strokeWidth) {
    if (_strokeWidth == strokeWidth) return;
    _strokeWidth = strokeWidth;
    notifyListeners();
  }

  // ---------- Pointer events ----------

  bool ownsPointer(int pointer) => _pointer == pointer;

  void onPointerDown(PointerDownEvent event, Offset canvasPosition) {
    if (event.buttons != kPrimaryButton || isDrawing) return;
    _pointer = event.pointer;
    _id = _uuid.v4();
    _start = canvasPosition;
    _end = canvasPosition;
    _buttons = event.buttons;
    notifyListeners();
  }

  void onPointerMove(PointerMoveEvent event, Offset canvasPosition) {
    if (!ownsPointer(event.pointer)) return;
    _end = canvasPosition;
    if (event.kind == PointerDeviceKind.mouse) {
      if (event.buttons & kPrimaryButton == 0) {
        _finish();
        return;
      }
      if (event.buttons & kSecondaryButton != 0 && _buttons & kSecondaryButton == 0) {
        _controls.add(canvasPosition);
      }
      _buttons = event.buttons;
    }
    notifyListeners();
  }

  void onPointerUp(PointerUpEvent event, Offset canvasPosition) {
    if (!ownsPointer(event.pointer)) return;
    _end = canvasPosition;
    _finish();
  }

  void _finish() {
    final id = _id;
    final start = _start;
    final end = _end;
    final arrow = id != null && start != null && end != null ? _newArrow(id, start, end) : null;
    _clearPreview();
    if (arrow != null) onArrow(arrow);
  }

  void onPointerCancel(PointerCancelEvent event) {
    if (!ownsPointer(event.pointer)) return;
    _clearPreview();
  }

  void cancel() {
    if (!isDrawing) return;
    _clearPreview();
  }

  // ---------- Private helpers ----------

  ArrowModel? _newArrow(String id, Offset start, Offset end) {
    if ((end - start).distance < arrowMinimumLength) return null;
    return ArrowModel(
      ArrowElementData(
        id: id,
        start: start,
        controls: _curveControls(start, end),
        end: end,
        color: _color.toARGB32(),
        strokeStyle: _strokeStyle,
        strokeWidth: _strokeWidth,
      ),
    );
  }

  List<Offset> _curveControls(Offset start, Offset end) =>
      _controls.isEmpty ? [arrowControlPoint(start: start, end: end)] : List.of(_controls);

  void _clearPreview() {
    _pointer = null;
    _id = null;
    _start = null;
    _end = null;
    _controls.clear();
    _buttons = 0;
    notifyListeners();
  }
}
