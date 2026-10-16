// Provides freehand stroke sampling, geometry, rendering, and editing state.
// Used by the canvas pen tool and persisted pen elements.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

part 'pen_geometry.dart';
part 'pen_preview.dart';
part 'pen_stroke.dart';
part 'pen_stroke_model.dart';

// ---------- Tool state ----------

/// Samples pointer input and current options for a freehand stroke.
/// Used by the canvas page to produce positioned pen element data.
class PenTool extends ChangeNotifier {
  // ---------- Construction ----------

  PenTool({required this.onStroke});

  final ValueChanged<RawPenStroke> onStroke;
  final _points = <PenPointData>[];
  int? _activePointer;
  Offset? _pointerPosition;
  Color _color = defaultCanvasColor;
  double _strokeWidth = 4;
  double _streamline = penStreamlineDefault;
  Color? _pendingColor;
  double? _pendingStrokeWidth;
  double? _pendingStreamline;

  // ---------- Options ----------

  bool get active => _activePointer != null;

  void setColor(Color color) {
    if (active) {
      _pendingColor = color;
    } else {
      _color = color;
      notifyListeners();
    }
  }

  void setStrokeWidth(double strokeWidth) {
    if (active) {
      _pendingStrokeWidth = strokeWidth;
    } else {
      _strokeWidth = strokeWidth;
      notifyListeners();
    }
  }

  void setStreamline(double streamline) {
    if (active) {
      _pendingStreamline = streamline;
    } else {
      _streamline = streamline;
      notifyListeners();
    }
  }

  // ---------- Pointer events ----------

  bool _isAllowedPointer(PointerDownEvent event) => switch (event.kind) {
    PointerDeviceKind.mouse => event.buttons & kPrimaryButton != 0,
    PointerDeviceKind.touch || PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
    _ => false,
  };

  double _pressure(PointerEvent event) {
    if (event.pressureMin == event.pressureMax) return 0.5;
    return ((event.pressure - event.pressureMin) / (event.pressureMax - event.pressureMin)).clamp(0.0, 1.0);
  }

  void _append(PointerEvent event) {
    final position = event.localPosition;
    if (_points.isNotEmpty && (position - _points.last.position).distanceSquared <= _minimumPointDistanceSquared) {
      return;
    }
    _points.add(PenPointData(position, pressure: _pressure(event)));
  }

  void onPointerDown(PointerDownEvent event) {
    if (active || !_isAllowedPointer(event)) return;
    _activePointer = event.pointer;
    _pointerPosition = event.localPosition;
    _append(event);
    notifyListeners();
  }

  void onPointerUpdate(PointerMoveEvent event) {
    if (active && event.pointer != _activePointer) return;
    _pointerPosition = event.localPosition;
    if (!active) {
      notifyListeners();
      return;
    }
    _append(event);
    notifyListeners();
  }

  void onPointerHover(PointerHoverEvent event) {
    if (active && event.pointer != _activePointer) return;
    _pointerPosition = event.localPosition;
    notifyListeners();
  }

  void onPointerUp(PointerUpEvent event) => _finish(event);

  void onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointer) cancel();
  }

  /// Discards the unfinished stroke and applies options queued for the next one.
  /// Used when navigation or a tool change takes over the pointer sequence.
  void cancel() {
    _pointerPosition = null;
    _clearStroke();
    notifyListeners();
  }

  void onPointerExit(PointerExitEvent event) {
    if (!active) {
      _pointerPosition = null;
      notifyListeners();
      return;
    }
    _finish(event);
  }

  // ---------- Private helpers ----------

  void _finish(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _pointerPosition = event is PointerExitEvent ? null : event.localPosition;
    _append(event);
    final stroke = (
      points: List<PenPointData>.of(_points),
      color: _color.toARGB32(),
      width: _strokeWidth,
      streamline: _streamline,
    );
    _clearStroke();
    onStroke(stroke);
    notifyListeners();
  }

  void _clearStroke() {
    _activePointer = null;
    _points.clear();
    final pendingColor = _pendingColor;
    final pendingWidth = _pendingStrokeWidth;
    final pendingStreamline = _pendingStreamline;
    _pendingColor = null;
    _pendingStrokeWidth = null;
    _pendingStreamline = null;
    if (pendingColor != null) _color = pendingColor;
    if (pendingWidth != null) _strokeWidth = pendingWidth;
    if (pendingStreamline != null) _streamline = pendingStreamline;
  }
}
