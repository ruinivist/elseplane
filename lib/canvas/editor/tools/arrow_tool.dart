// Samples pointer gestures and retains drafts for newly created arrows.
// CanvasInput owns pointer arbitration; EditorSession commits accepted values.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/geometry/arrow_anchor_geometry.dart';
import 'package:elseplane/canvas/geometry/arrow_geometry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:uuid/uuid.dart';

// ---------- Tool state ----------

/// Tracks pointer input while creating arrows on the canvas.
/// Used by CanvasInput to produce immutable arrow values.
class ArrowTool extends ChangeNotifier {
  // ---------- Construction ----------

  ArrowTool({
    required this.session,
    required this.onArrow,
    this.snapArrow,
    this.resolveAnchor,
    this.screenToCanvas,
  });

  final EditorSession Function() session;
  final ValueChanged<ArrowElementData> onArrow;
  final ArrowSnap? Function(Offset)? snapArrow;
  final Offset? Function(ArrowAttachment)? resolveAnchor;
  final Offset Function(Offset)? screenToCanvas;
  final _uuid = const Uuid();
  int? _pointer;
  String? _id;
  Offset? _rawStart;
  Offset? _rawEnd;
  Offset? _screenStart;
  Offset? _screenEnd;
  ArrowSnap? _startSnap;
  Offset? get _start {
    final snap = _startSnap;
    return snap == null ? _rawStart : resolveAnchor?.call(snap.attachment) ?? snap.position;
  }

  Offset? get _requestedEnd {
    final screen = _screenEnd;
    return screen == null ? _rawEnd : screenToCanvas?.call(screen) ?? _rawEnd;
  }

  final _controls = <Offset>[];
  int _buttons = 0;
  Color get _color => session().defaults.arrowColor;
  ArrowStrokeStyle get _strokeStyle => session().defaults.arrowStyle;
  double get _strokeWidth => session().defaults.arrowWidth;

  // ---------- Options and preview ----------

  bool get isDrawing => _pointer != null;
  Color get color => _color;
  ArrowStrokeStyle get strokeStyle => _strokeStyle;
  double get strokeWidth => _strokeWidth;

  ArrowPreview? get preview {
    final start = _start;
    final requested = _requestedEnd;
    if (start == null || requested == null) return null;
    final initial = _screenEnd == null;
    final snap = initial ? _startSnap : snapArrow?.call(requested);
    final end = initial ? start : snap?.position ?? requested;
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
      snapPoints: [if (snap != null) end],
    );
  }

  void setColor(Color color) {
    if (_color == color) return;
    session().setDrawingDefaults(session().defaults.copyWith(arrowColor: color));
    notifyListeners();
  }

  void setStrokeStyle(ArrowStrokeStyle strokeStyle) {
    if (_strokeStyle == strokeStyle) return;
    session().setDrawingDefaults(session().defaults.copyWith(arrowStyle: strokeStyle));
    notifyListeners();
  }

  void setStrokeWidth(double strokeWidth) {
    if (_strokeWidth == strokeWidth) return;
    session().setDrawingDefaults(session().defaults.copyWith(arrowWidth: strokeWidth));
    notifyListeners();
  }

  // ---------- Pointer events ----------

  bool ownsPointer(int pointer) => _pointer == pointer;

  void onPointerDown(PointerDownEvent event, Offset canvasPosition) {
    if (event.buttons != kPrimaryButton || isDrawing) return;
    _pointer = event.pointer;
    _id = _uuid.v4();
    _rawStart = _rawEnd = canvasPosition;
    _screenStart = event.localPosition;
    _startSnap = snapArrow?.call(canvasPosition);
    _buttons = event.buttons;
    notifyListeners();
  }

  void onPointerMove(PointerMoveEvent event, Offset canvasPosition) {
    if (!ownsPointer(event.pointer)) return;
    _sampleEnd(event.localPosition, canvasPosition);
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
    _sampleEnd(event.localPosition, canvasPosition);
    _finish();
  }

  void _finish() {
    final id = _id;
    final start = _start;
    final requested = _requestedEnd;
    final arrow = id != null && start != null && requested != null ? _newArrow(id, start, requested) : null;
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

  void _sampleEnd(Offset screen, Offset position) {
    _screenEnd = screen;
    _rawEnd = position;
  }

  ArrowElementData? _newArrow(String id, Offset start, Offset requested) {
    final dragStart = screenToCanvas?.call(_screenStart!) ?? _rawStart!;
    if ((requested - dragStart).distance < arrowMinimumLength) return null;
    final snap = snapArrow?.call(requested);
    final end = snap?.position ?? requested;
    if ((end - start).distance < arrowMinimumLength) {
      return null;
    }
    return ArrowElementData(
      id: id,
      start: start,
      controls: _curveControls(start, end),
      end: end,
      startAttachment: _startSnap?.attachment,
      endAttachment: snap?.attachment,
      color: _color,
      strokeStyle: _strokeStyle,
      strokeWidth: _strokeWidth,
    );
  }

  List<Offset> _curveControls(Offset start, Offset end) =>
      _controls.isEmpty ? [arrowControlPoint(start: start, end: end)] : List.of(_controls);

  void _clearPreview() {
    _pointer = null;
    _id = null;
    _rawStart = null;
    _rawEnd = null;
    _screenStart = null;
    _screenEnd = null;
    _startSnap = null;
    _controls.clear();
    _buttons = 0;
    notifyListeners();
  }
}

// ---------- Control geometry ----------

/// Places the control point that gives a new arrow its default bend.
/// Used while previewing and committing arrows from pointer drags.
Offset arrowControlPoint({
  required Offset start,
  required Offset end,
}) {
  final vector = end - start;
  final length = vector.distance;
  if (length == 0) return start;

  final bendLength = (length * 0.09).clamp(6.0, 32.0);
  final normal = Offset(vector.dy / length, -vector.dx / length);

  return start + vector * 0.5 + normal * bendLength;
}

typedef ArrowPreview = ({
  ArrowGeometry geometry,
  Color color,
  ArrowStrokeStyle strokeStyle,
  double strokeWidth,
  bool showControls,
  List<Offset> snapPoints,
});
