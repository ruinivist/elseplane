// Arbitrates canvas pointer sequences and groups accepted editor operations.
// Used by CanvasView and element controls through lifetime-bound input targets.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/tools/arrow_tool.dart';
import 'package:elseplane/canvas/editor/tools/pen_tool.dart';
import 'package:elseplane/canvas/editor/tools/shape_tool.dart';
import 'package:elseplane/canvas/geometry/arrow_anchor_geometry.dart';
import 'package:elseplane/canvas/geometry/pen_geometry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

bool _supportsCanvasEditing(PointerDeviceKind kind) => switch (kind) {
  PointerDeviceKind.mouse || PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
  _ => false,
};

// ---------- View boundary ----------

/// Supplies measured viewport operations without giving input ownership of the grid.
/// Implemented by the document-to-grid projection.
abstract interface class CanvasInputViewport {
  double get scale;
  Offset globalToScreen(Offset globalPosition);
  void stopAnimation();
  Offset screenToCanvas(Offset screenPosition);
  Iterable<String> overlapping(Rect screenRect);
  Iterable<String> hitTest(Offset globalPosition);
  void startPan(Offset screenPosition);
  void updatePan(Offset screenPosition, Offset screenDelta);
  void endPan(Velocity velocity);
}

// ---------- Gesture states ----------

sealed class _Gesture {
  const _Gesture(this.pointer);
  final int pointer;
}

final class _ObjectGesture extends _Gesture {
  _ObjectGesture(super.pointer, this.id, this.selection, {required this.modified, required this.spaceHeld});
  final String id;
  final Set<String> selection;
  final bool modified;
  final bool spaceHeld;
  bool transforming = false;
}

final class _PanGesture extends _Gesture {
  _PanGesture(PointerDownEvent event, this.start, this.slop, {this.menuTarget})
    : velocity = (VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, start)),
      super(event.pointer);
  final Offset start;
  final double slop;
  final VelocityTracker velocity;
  final String? menuTarget;
  bool started = false;
}

final class _MarqueeGesture extends _Gesture {
  _MarqueeGesture(super.pointer, this.start, this.slop, this.selection, {required this.toggle});
  final Offset start;
  final double slop;
  final Set<String> selection;
  final bool toggle;
  Offset? end;
}

final class _DrawingGesture extends _Gesture {
  const _DrawingGesture(super.pointer);
}

final class _ArrowDragGesture extends _Gesture {
  _ArrowDragGesture(super.pointer, this.id, this.start, this.slop, this.selection);
  final String id;
  final Set<String> selection;
  final Offset start;
  final double slop;
  bool moving = false;
}

final class _EraserGesture extends _Gesture {
  const _EraserGesture(super.pointer);
}

final class _QuickTextTap {
  _QuickTextTap(this.down, {this.previous});
  final PointerDownEvent down;
  _QuickTextTap? previous;
  CanvasInputTarget? shapeTarget;
  bool resolved = false;
  bool empty = false;
  Duration? released;

  void resolveEmpty() {
    resolved = true;
    empty = true;
    if (previous?.empty != true) previous = null;
  }

  void resolveShape(CanvasInputTarget target) {
    resolved = true;
    shapeTarget = target;
    final earlier = previous?.shapeTarget;
    if (earlier == null || earlier.id != target.id || !identical(earlier._lifetime, target._lifetime)) {
      previous = null;
    }
  }
}

// ---------- Pointer ownership ----------

/// Owns pointer arbitration, creation drafts, and interaction cancellation.
/// The session remains the sole document writer; views supply focus and layout effects.
class CanvasInput extends ChangeNotifier {
  CanvasInput({
    required this.session,
    required this.viewport,
    required this.enabled,
    required this.panSlop,
    required this.onCloseMenu,
    required this.onOpenMenu,
    required this.onEndEditing,
    required this.onEndShapeEditing,
    required this.onFocusElement,
    required this.onPlace,
    required this.onQuickText,
    required this.isFocusedEditorAt,
    required this.onStroke,
    required this.onArrow,
    required this.onShape,
    ArrowSnap? Function(Offset)? snapArrow,
    Offset? Function(ArrowAttachment)? resolveArrowAnchor,
    void Function(Iterable<String>)? removeElements,
  }) : _removeElements = removeElements ?? session.remove {
    pen = PenTool(session: () => session, onStroke: onStroke);
    arrow = ArrowTool(
      session: () => session,
      onArrow: onArrow,
      snapArrow: snapArrow,
      resolveAnchor: resolveArrowAnchor,
      screenToCanvas: viewport.screenToCanvas,
    );
    shape = ShapeTool(session: () => session, onShape: onShape);
    arrow.addListener(notifyListeners);
    shape.addListener(notifyListeners);
    modifierPressed.addListener(_modifierChanged);
    _restoration = session.restorationGeneration;
    _tool = session.tool;
    _observedDocument = session.document;
    session.addListener(_sessionChanged);
  }

  final EditorSession session;
  final CanvasInputViewport viewport;
  final bool Function() enabled;
  final double Function(PointerDeviceKind) panSlop;
  final VoidCallback onCloseMenu;
  final void Function(String? id, Offset globalPosition) onOpenMenu;
  final void Function({bool commitMediaDraft}) onEndEditing;
  final VoidCallback onEndShapeEditing;
  final void Function(String id, {bool edit}) onFocusElement;
  final ValueChanged<Offset> onPlace;
  final ValueChanged<Offset> onQuickText;
  final bool Function(Offset globalPosition) isFocusedEditorAt;
  final ValueChanged<RawPenStroke> onStroke;
  final ValueChanged<ArrowElementData> onArrow;
  final ValueChanged<ShapeElementData> onShape;
  final void Function(Iterable<String>) _removeElements;
  late final PenTool pen;
  late final ArrowTool arrow;
  late final ShapeTool shape;
  final ValueNotifier<bool> modifierPressed = ValueNotifier(false);
  final pointerPosition = ValueNotifier<Offset?>(null);
  final _pointers = <int, PointerDeviceKind>{};
  final _blockedPointers = <int>{};
  _Gesture? _gesture;
  _QuickTextTap? _quickTextTap;
  bool _spaceHeld = false;
  int _generation = 0;
  late int _restoration;
  late CanvasTool _tool;
  late CanvasDocument _observedDocument;
  bool _disposed = false;
  bool _promotingForActivation = false;

  void _modifierChanged() {
    if (modifierPressed.value) cancelQuickText();
  }

  bool get blocked => !enabled() || _blockedPointers.isNotEmpty;
  bool get spaceHeld => _spaceHeld;
  set spaceHeld(bool value) {
    if (_spaceHeld == value) return;
    _spaceHeld = value;
    if (value) cancelQuickText();
    notifyListeners();
  }

  Rect? get marquee => switch (_gesture) {
    _MarqueeGesture(:final start, end: final end?) => Rect.fromPoints(start, end),
    _ => null,
  };
  Set<String> get selectionBeforePointer => switch (_gesture) {
    _ObjectGesture(:final selection) => selection,
    _ => session.selectedIds,
  };
  bool hasPointer(int pointer) => _pointers.containsKey(pointer);
  bool get placing => switch (session.tool) {
    CanvasTool.text || CanvasTool.code || CanvasTool.media => true,
    _ => false,
  };

  CanvasInputTarget target(String id) => CanvasInputTarget._(this, id);

  void _sessionChanged() {
    final document = session.document;
    if (!identical(document, _observedDocument)) {
      if (!_promotingForActivation || !_sameElements(_observedDocument, document)) cancelQuickText();
      _observedDocument = document;
    }
    if (!session.isLive || _restoration != session.restorationGeneration || _tool != session.tool) {
      interrupt();
      _restoration = session.restorationGeneration;
      _tool = session.tool;
    }
  }

  bool _sameElements(CanvasDocument first, CanvasDocument second) {
    if (first.background != second.background || first.elements.length != second.elements.length) return false;
    final old = {for (final value in first.elements) value.id: value};
    return second.elements.every((value) => identical(old[value.id], value));
  }

  void chooseTool(CanvasTool tool) {
    if (!enabled()) return;
    endInteraction();
    session.chooseTool(tool);
  }

  void toggleTool(CanvasTool tool) => chooseTool(session.tool == tool ? CanvasTool.select : tool);

  void finishOperation() {
    session.finishOperation();
    if (_gesture case final _ObjectGesture gesture) gesture.transforming = false;
  }

  void interrupt() {
    if (_disposed) return;
    _generation++;
    cancelQuickText();
    _blockedPointers.addAll(_pointers.keys);
    _cancelGesture();
    spaceHeld = false;
  }

  void endInteraction({bool commitMediaDraft = true}) {
    onCloseMenu();
    interrupt();
    session.finishOperation();
    onEndEditing(commitMediaDraft: commitMediaDraft);
  }

  void _cancelGesture() {
    pen.cancel();
    arrow.cancel();
    shape.cancel();
    final gesture = _gesture;
    _gesture = null;
    if (gesture is _MarqueeGesture) session.setSelection(gesture.selection);
    if (gesture is _ObjectGesture && gesture.transforming ||
        gesture is _EraserGesture ||
        gesture is _ArrowDragGesture) {
      session.finishOperation();
    }
    notifyListeners();
  }

  bool canHandle(PointerEvent event) {
    if (_disposed || !_supportsCanvasEditing(event.kind)) return false;
    if (blocked) return false;
    final gesture = _gesture;
    if (event is PointerDownEvent &&
        gesture != null &&
        gesture.pointer != event.pointer &&
        _pointers.containsKey(gesture.pointer)) {
      return false;
    }
    return true;
  }

  void _observeDown(PointerDownEvent event) {
    if (_disposed || !_supportsCanvasEditing(event.kind)) return;
    if (_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.kind;
    if (blocked) _blockedPointers.add(event.pointer);
    final previous = _quickTextTap;
    final second =
        previous?.released != null &&
        previous!.down.kind == event.kind &&
        previous.resolved &&
        event.timeStamp >= previous.released! &&
        event.timeStamp - previous.released! <= kDoubleTapTimeout &&
        event.timeStamp - previous.down.timeStamp >= kDoubleTapMinTime &&
        (event.position - previous.down.position).distance <= kDoubleTapSlop;
    if (!canHandle(event) ||
        session.tool != CanvasTool.select ||
        spaceHeld ||
        modifierPressed.value ||
        event.buttons != kPrimaryButton ||
        event.kind != PointerDeviceKind.mouse ||
        isFocusedEditorAt(event.position)) {
      cancelQuickText();
    } else {
      _quickTextTap = _QuickTextTap(event, previous: second ? previous : null);
    }
  }

  void cancelQuickText() => _quickTextTap = null;

  bool _completeQuickText(PointerUpEvent event) {
    final tap = _quickTextTap;
    if (tap == null || tap.down.pointer != event.pointer) return false;
    if ((event.position - tap.down.position).distance > panSlop(event.kind) || spaceHeld || modifierPressed.value) {
      cancelQuickText();
      return false;
    }
    if (!tap.resolved) {
      if (viewport.hitTest(tap.down.position).isNotEmpty) {
        cancelQuickText();
        return false;
      }
      tap.resolveEmpty();
    }
    final previous = tap.previous;
    if (previous == null || previous.released == null || !previous.resolved) {
      tap.released = event.timeStamp;
      return false;
    }
    cancelQuickText();
    if (tap.empty) {
      final position = viewport.screenToCanvas(viewport.globalToScreen(tap.down.position));
      endInteraction();
      session.setSelection(const []);
      onQuickText(position);
    } else {
      final target = tap.shapeTarget;
      if (target == null || !target.attached) return false;
      target.activate(edit: true);
    }
    return true;
  }

  void pointerDown(PointerDownEvent event) {
    if (!_supportsCanvasEditing(event.kind)) return;
    final seen = _pointers.containsKey(event.pointer);
    _observeDown(event);
    pointerPosition.value = event.localPosition;
    if (seen || !canHandle(event)) return;
    if (session.tool == CanvasTool.eraser && !spaceHeld) {
      if (event.kind != PointerDeviceKind.mouse || event.buttons == kPrimaryButton) {
        _gesture = _EraserGesture(event.pointer);
        _erase(event.position);
      }
      return;
    }
    if (session.tool == CanvasTool.pen && !spaceHeld) {
      _gesture = _DrawingGesture(event.pointer);
      pen.onPointerDown(event);
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kSecondaryButton &&
        session.tool == CanvasTool.select) {
      viewport.stopAnimation();
      _gesture = _PanGesture(event, event.localPosition, 4);
      return;
    }
    if (event.buttons != kPrimaryButton) return;
    final position = viewport.screenToCanvas(event.localPosition);
    if (placing) {
      onPlace(position);
      return;
    }
    if (session.tool == CanvasTool.arrow || session.tool == CanvasTool.shape) {
      _gesture = _DrawingGesture(event.pointer);
      if (session.tool == CanvasTool.arrow) arrow.onPointerDown(event, position);
      if (session.tool == CanvasTool.shape) shape.onPointerDown(event, position);
      return;
    }
    onEndEditing();
    final previous = session.selectedIds;
    final toggle = modifierPressed.value;
    if (!toggle) session.setSelection(const []);
    if (event.kind != PointerDeviceKind.mouse) return;
    _gesture = _MarqueeGesture(event.pointer, event.localPosition, panSlop(event.kind), previous, toggle: toggle);
    notifyListeners();
  }

  void pointerMove(PointerMoveEvent event) {
    if (!canHandle(event)) return;
    pointerPosition.value = event.localPosition;
    final tap = _quickTextTap;
    if (tap != null &&
        tap.down.pointer == event.pointer &&
        ((event.position - tap.down.position).distance > panSlop(event.kind) ||
            (event.position - tap.down.position).distance > kDoubleTapTouchSlop)) {
      cancelQuickText();
    }
    switch (_gesture) {
      case final _PanGesture pan when pan.pointer == event.pointer:
        pan.velocity.addPosition(event.timeStamp, event.localPosition);
        final displacement = event.localPosition - pan.start;
        if (!pan.started && displacement.distance <= pan.slop) return;
        if (!pan.started) viewport.startPan(pan.start);
        viewport.updatePan(event.localPosition, pan.started ? event.localDelta : displacement);
        pan.started = true;
      case final _DrawingGesture drawing when drawing.pointer == event.pointer:
        if (session.tool == CanvasTool.pen) pen.onPointerUpdate(event);
        if (session.tool == CanvasTool.arrow) arrow.onPointerMove(event, viewport.screenToCanvas(event.localPosition));
        if (session.tool == CanvasTool.shape) shape.onPointerMove(event, viewport.screenToCanvas(event.localPosition));
      case final _EraserGesture eraser when eraser.pointer == event.pointer:
        _erase(event.position);
      case final _ArrowDragGesture arrow when arrow.pointer == event.pointer:
        final displacement = event.position - arrow.start;
        if (!arrow.moving && displacement.distance <= arrow.slop) return;
        _move(arrow.id, arrow.moving ? event.delta : displacement);
        arrow.moving = true;
      case final _MarqueeGesture marquee when marquee.pointer == event.pointer:
        _updateMarquee(marquee, event.localPosition);
      default:
        if (session.tool == CanvasTool.pen) pen.onPointerUpdate(event);
    }
  }

  void pointerUp(PointerUpEvent event) {
    if (!_supportsCanvasEditing(event.kind)) return;
    final allowed = canHandle(event);
    _pointers.remove(event.pointer);
    _blockedPointers.remove(event.pointer);
    if (!allowed) return;
    if (_completeQuickText(event)) return;
    final gesture = _gesture;
    if (gesture?.pointer != event.pointer) return;
    switch (gesture) {
      case _ObjectGesture():
        // Tap and drag recognizers apply their final edits after raw release.
        // Their lifetime-bound targets finish the operation after those edits.
        return;
      case final _PanGesture pan:
        _gesture = null;
        if (pan.started) {
          pan.velocity.addPosition(event.timeStamp, event.localPosition);
          viewport.endPan(pan.velocity.getVelocity());
        } else if ((event.localPosition - pan.start).distance <= pan.slop) {
          onOpenMenu(pan.menuTarget, event.position);
        }
      case _DrawingGesture():
        _gesture = null;
        if (session.tool == CanvasTool.pen) pen.onPointerUp(event);
        if (session.tool == CanvasTool.arrow) arrow.onPointerUp(event, viewport.screenToCanvas(event.localPosition));
        if (session.tool == CanvasTool.shape) shape.onPointerUp(event, viewport.screenToCanvas(event.localPosition));
      case final _ArrowDragGesture arrow:
        _gesture = null;
        if (!arrow.moving) {
          session.setSelection(const []);
          _activate(arrow.id);
        }
        session.finishOperation();
      case final _MarqueeGesture marquee:
        _updateMarquee(marquee, event.localPosition);
        _gesture = null;
      case _EraserGesture():
        _gesture = null;
        session.finishOperation();
      case null:
        break;
    }
    notifyListeners();
  }

  void pointerCancel(PointerCancelEvent event) {
    if (!_supportsCanvasEditing(event.kind)) return;
    cancelQuickText();
    _pointers.remove(event.pointer);
    _blockedPointers.remove(event.pointer);
    if (_gesture?.pointer == event.pointer) {
      _generation++;
      _cancelGesture();
    }
  }

  void hover(PointerHoverEvent event) {
    if (!_supportsCanvasEditing(event.kind)) return;
    pointerPosition.value = event.localPosition;
    if (session.tool == CanvasTool.pen && !spaceHeld && !blocked) pen.onPointerHover(event);
  }

  void exit(PointerExitEvent event) {
    if (!_supportsCanvasEditing(event.kind)) return;
    pointerPosition.value = null;
    if (session.tool == CanvasTool.pen && !blocked) pen.onPointerExit(event);
  }

  void _updateMarquee(_MarqueeGesture gesture, Offset end) {
    if (gesture.end == null && (end - gesture.start).distance <= gesture.slop) return;
    if (gesture.end == null) onEndEditing();
    gesture.end = end;
    final overlaps = viewport.overlapping(Rect.fromPoints(gesture.start, end)).toSet();
    session.setSelection(
      gesture.toggle
          ? {...gesture.selection.difference(overlaps), ...overlaps.difference(gesture.selection)}
          : overlaps,
    );
    notifyListeners();
  }

  void _erase(Offset globalPosition) => _removeElements(viewport.hitTest(globalPosition));

  void _resolveQuickTextTarget(CanvasInputTarget target, PointerDownEvent event, {required bool control}) {
    if (control) {
      cancelQuickText();
      if (session.editing == (id: target.id, field: EditorField.shapeText)) onEndShapeEditing();
      return;
    }
    final tap = _quickTextTap;
    if (tap == null || tap.down.pointer != event.pointer) return;
    if (!target.attached || session.element(target.id) is! ShapeElementData || event.kind != PointerDeviceKind.mouse) {
      cancelQuickText();
      return;
    }
    tap.resolveShape(target);
  }

  void _activate(String id, {bool edit = false}) {
    if (blocked || session.element(id) == null) return;
    if (session.editing != null && session.editing?.id != id) session.editField(null);
    _promotingForActivation = true;
    try {
      session.promoteAuto([id]);
    } finally {
      _promotingForActivation = false;
    }
    session.setActive(id);
    onFocusElement(id, edit: edit);
  }

  void _beginTransform() {
    if (_gesture case final _ObjectGesture gesture when !gesture.transforming) {
      session.finishOperation();
      gesture.transforming = true;
    } else if (_gesture case _ArrowDragGesture(moving: false)) {
      session.finishOperation();
    }
  }

  void _move(String id, Offset screenDelta) {
    if (blocked || session.tool != CanvasTool.select || modifierPressed.value || screenDelta == Offset.zero) return;
    final value = session.element(id);
    if (value == null) return;
    var selected = session.isSelected(id);
    if (_gesture case _ObjectGesture(selection: final before) when before.contains(id)) {
      session.setSelection(before);
      selected = true;
    }
    if (_gesture case _ArrowDragGesture(selection: final before) when before.contains(id)) {
      session.setSelection(before);
      selected = true;
    }
    if (!selected) session.setSelection(const []);
    final ids = selected ? session.selectedIds : {id};
    _beginTransform();
    session.move(ids, screenDelta / viewport.scale);
  }

  void undo() {
    endInteraction(commitMediaDraft: false);
    session.undo();
  }

  void redo() {
    endInteraction(commitMediaDraft: false);
    session.redo();
  }

  @override
  void dispose() {
    cancelQuickText();
    _disposed = true;
    _generation++;
    session.removeListener(_sessionChanged);
    arrow.removeListener(notifyListeners);
    shape.removeListener(notifyListeners);
    pen.dispose();
    arrow.dispose();
    shape.dispose();
    modifierPressed.dispose();
    pointerPosition.dispose();
    super.dispose();
  }
}

// ---------- Element and control bindings ----------

/// Captures a target lifetime and gesture generation for element callbacks.
/// Retained by the view so canceled recognizers cannot mutate later interactions.
class CanvasInputTarget {
  CanvasInputTarget._(this.input, this.id)
    : _lifetime = input.session.elementLifetime(id),
      _contextGeneration = input._generation;
  final CanvasInput input;
  final String id;
  final Object? _lifetime;
  _Gesture? _sequence;
  final int _contextGeneration;
  bool get attached =>
      _lifetime != null &&
      !input._disposed &&
      _contextGeneration == input._generation &&
      identical(_lifetime, input.session.elementLifetime(id));
  bool get current => attached && !input.blocked && _sequence != null && identical(_sequence, input._gesture);

  void pointerDown(PointerDownEvent event, {bool control = false}) {
    if (!attached || !_supportsCanvasEditing(event.kind)) return;
    input
      .._observeDown(event)
      .._resolveQuickTextTarget(this, event, control: control);
    if (!input.canHandle(event) || !attached) return;
    if (input._gesture case _ObjectGesture(:final pointer, id: final target)
        when pointer == event.pointer && target == id) {
      _sequence = input._gesture;
      return;
    }
    if (event.buttons == kSecondaryButton && input.session.tool == CanvasTool.select) {
      input.viewport.stopAnimation();
      input._gesture = _PanGesture(
        event,
        input.viewport.globalToScreen(event.position),
        4,
        menuTarget: id,
      );
      _sequence = input._gesture;
      return;
    }
    if (event.buttons != kPrimaryButton || input.session.tool != CanvasTool.select) return;
    final session = input.session;
    final value = session.element(id);
    if (value == null) return;
    final selection = session.selectedIds;
    input._gesture = _ObjectGesture(
      event.pointer,
      id,
      selection,
      modified: control || input.modifierPressed.value,
      spaceHeld: input.spaceHeld,
    );
    _sequence = input._gesture;
    if (control) {
      if (!input.modifierPressed.value) session.setSelection(const []);
      return;
    }
    if (input.modifierPressed.value) {
      session
        ..finishOperation()
        ..setSelection(selection.contains(id) ? selection.difference({id}) : {...selection, id})
        ..promoteAuto([id])
        ..finishOperation();
      return;
    }
    if (session.activeId != id && session.editing?.id != id) {
      session.setActive(null);
      input.onEndEditing();
    }
    if (session.editing?.field == EditorField.markdown && (value is! TextElementData || session.editing?.id != id)) {
      session.editField(null);
    }
    if (session.editing?.field == EditorField.shapeText && (value is! ShapeElementData || session.editing?.id != id)) {
      session.editField(null);
    }
    session.setSelection(const []);
    if (value is ArrowElementData) {
      input._gesture = _ArrowDragGesture(event.pointer, id, event.position, input.panSlop(event.kind), selection);
      _sequence = input._gesture;
    }
  }

  void activate({bool edit = false, VoidCallback? afterActivate, bool fromPointer = false}) {
    if (!attached || input.blocked || input.modifierPressed.value) return;
    final sequence = _sequence;
    if (afterActivate != null) {
      if (input.session.tool != CanvasTool.select ||
          input.spaceHeld ||
          sequence is _ObjectGesture && (sequence.modified || sequence.spaceHeld) ||
          sequence != null && !current) {
        return;
      }
      if (fromPointer && (sequence is! _ObjectGesture || sequence.id != id || sequence.transforming || !current)) {
        return;
      }
    }
    final generation = input._generation;
    input._activate(id, edit: edit);
    _finishClick();
    if (afterActivate != null &&
        attached &&
        !input.blocked &&
        !input.modifierPressed.value &&
        input.session.tool == CanvasTool.select &&
        !input.spaceHeld &&
        generation == input._generation &&
        input.session.activeId == id) {
      afterActivate();
    }
  }

  void move(Offset delta) {
    if (current) input._move(id, delta);
  }

  void transform(VoidCallback edit) {
    if (!current) return;
    input._beginTransform();
    edit();
  }

  void finish() {
    if (!current) return;
    input.finishOperation();
    if (input._gesture case _ObjectGesture(id: final target) when target == id) input._gesture = null;
    _sequence = null;
  }

  void interact() {
    if (!attached || input.blocked) return;
    input.session.promoteAuto([id]);
    _finishClick();
  }

  void _finishClick() {
    // Focused content editors retain their logical typing operation. A callback
    // from another pointer sequence cannot finish the current gesture's edits.
    if (input._gesture case _ObjectGesture(transforming: false) when current && input.session.editing == null) {
      finish();
    }
  }
}
