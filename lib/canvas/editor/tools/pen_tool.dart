// Provides freehand stroke sampling, geometry, rendering, and editing state.
// Used by the canvas pen tool and persisted pen elements.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/geometry/pen_geometry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

export 'package:elseplane/canvas/geometry/pen_geometry.dart';

// ---------- Sampling ----------

const _minimumPointDistanceSquared = 4.0;

// ---------- Tool state ----------

/// Samples pointer input and current options for a freehand stroke.
/// Used by the canvas page to produce positioned pen element data.
class PenTool extends ChangeNotifier {
  // ---------- Construction ----------

  PenTool({required this.session, required this.onStroke});

  final EditorSession Function() session;
  final ValueChanged<RawPenStroke> onStroke;
  final _points = <PenPointData>[];
  int? _activePointer;
  Offset? _pointerPosition;
  DrawingDefaults? _strokeDefaults;
  Color get _color => (_strokeDefaults ?? session().defaults).color;
  double get _strokeWidth => (_strokeDefaults ?? session().defaults).width;
  double get _streamline => (_strokeDefaults ?? session().defaults).streamline;

  List<PenPointData> get points => List.unmodifiable(_points);
  Offset? get pointerPosition => _pointerPosition;
  Color get color => _color;
  double get strokeWidth => _strokeWidth;
  double get streamline => _streamline;

  // ---------- Options ----------

  bool get active => _activePointer != null;

  void setColor(Color color) {
    session().setDrawingDefaults(session().defaults.copyWith(color: color));
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    session().setDrawingDefaults(session().defaults.copyWith(width: width));
    notifyListeners();
  }

  void setStreamline(double streamline) {
    session().setDrawingDefaults(session().defaults.copyWith(streamline: streamline));
    notifyListeners();
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
    _strokeDefaults = session().defaults;
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
      color: _color,
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
    _strokeDefaults = null;
  }
}
