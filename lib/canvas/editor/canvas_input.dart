// Arbitrates canvas pointer sequences and groups accepted editor operations.
// Used by CanvasView and element controls through lifetime-bound input targets.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/tools/arrow_tool.dart';
import 'package:elseplane/canvas/editor/tools/pen_tool.dart';
import 'package:elseplane/canvas/editor/tools/shape_tool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

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
  _ObjectGesture(super.pointer, this.id, this.selection);
  final String id;
  final Set<String> selection;
  bool transforming = false;
}

final class _PanGesture extends _Gesture {
  _PanGesture(PointerDownEvent event, this.start, this.slop, {this.menuTarget, this.secondary = false})
    : velocity = (VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, start)),
      super(event.pointer);
  final Offset start;
  final double slop;
  final VelocityTracker velocity;
  final String? menuTarget;
  final bool secondary;
  bool started = false;
}

final class _PlacementGesture extends _Gesture {
  const _PlacementGesture(super.pointer, this.start, this.tool, this.slop);
  final Offset start;
  final CanvasTool tool;
  final double slop;
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
    required this.onFocusElement,
    required this.onPlace,
    required this.onStroke,
    required this.onArrow,
    required this.onShape,
  }) {
    pen = PenTool(session: () => session, onStroke: onStroke);
    arrow = ArrowTool(session: () => session, onArrow: onArrow);
    shape = ShapeTool(session: () => session, onShape: onShape);
    pen.addListener(notifyListeners);
    arrow.addListener(notifyListeners);
    shape.addListener(notifyListeners);
    _restoration = session.restorationGeneration;
    _tool = session.tool;
    session.addListener(_sessionChanged);
  }

  final EditorSession session;
  final CanvasInputViewport viewport;
  final bool Function() enabled;
  final double Function(PointerDeviceKind) panSlop;
  final VoidCallback onCloseMenu;
  final void Function(String? id, Offset globalPosition) onOpenMenu;
  final void Function({bool commitMediaDraft}) onEndEditing;
  final void Function(String id, {bool edit}) onFocusElement;
  final ValueChanged<Offset> onPlace;
  final ValueChanged<RawPenStroke> onStroke;
  final ValueChanged<ArrowElementData> onArrow;
  final ValueChanged<ShapeElementData> onShape;
  late final PenTool pen;
  late final ArrowTool arrow;
  late final ShapeTool shape;
  final ValueNotifier<bool> modifierPressed = ValueNotifier(false);
  final pointerPosition = ValueNotifier<Offset?>(null);
  final _pointers = <int, PointerDeviceKind>{};
  final _blockedPointers = <int>{};
  _Gesture? _gesture;
  bool _navigating = false;
  bool _spaceHeld = false;
  int _generation = 0;
  late int _restoration;
  late CanvasTool _tool;
  bool _disposed = false;

  bool get blocked => !enabled() || _navigating || _blockedPointers.isNotEmpty;
  bool get spaceHeld => _spaceHeld;
  set spaceHeld(bool value) {
    if (_spaceHeld == value) return;
    _spaceHeld = value;
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
    if (!session.isLive || _restoration != session.restorationGeneration || _tool != session.tool) {
      interrupt();
      _restoration = session.restorationGeneration;
      _tool = session.tool;
    }
  }

  void chooseTool(CanvasTool tool, {bool touchSelectionEnabled = false}) {
    if (!enabled()) return;
    endInteraction();
    session.chooseTool(tool, touchSelectionEnabled: touchSelectionEnabled);
  }

  void toggleTool(CanvasTool tool) => chooseTool(session.tool == tool ? CanvasTool.select : tool);

  void finishOperation() {
    session.finishOperation();
    if (_gesture case final _ObjectGesture gesture) gesture.transforming = false;
  }

  void interrupt() {
    if (_disposed) return;
    _generation++;
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

  void navigationChanged({required bool active}) {
    if (_disposed) return;
    _navigating = active;
    if (active) {
      onCloseMenu();
      interrupt();
      pointerPosition.value = null;
    }
    notifyListeners();
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
    if (_disposed) return false;
    if (blocked) return false;
    final gesture = _gesture;
    if (event is PointerDownEvent &&
        gesture != null &&
        gesture.pointer != event.pointer &&
        _pointers.containsKey(gesture.pointer)) {
      return false;
    }
    return event is! PointerDownEvent ||
        event.kind != PointerDeviceKind.touch ||
        !_pointers.entries.any((entry) => entry.key != event.pointer && entry.value == PointerDeviceKind.touch);
  }

  void _observeDown(PointerDownEvent event) {
    if (_disposed) return;
    if (_pointers.containsKey(event.pointer)) return;
    final anotherTouch = event.kind == PointerDeviceKind.touch && _pointers.values.contains(PointerDeviceKind.touch);
    _pointers[event.pointer] = event.kind;
    if (anotherTouch) {
      onCloseMenu();
      interrupt();
    }
    if (blocked) _blockedPointers.add(event.pointer);
  }

  void pointerDown(PointerDownEvent event) {
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
      _gesture = _PanGesture(event, event.localPosition, 4, secondary: true);
      return;
    }
    if (event.buttons != kPrimaryButton) return;
    final position = viewport.screenToCanvas(event.localPosition);
    if (placing) {
      if (event.kind == PointerDeviceKind.touch) {
        _gesture = _PlacementGesture(event.pointer, event.localPosition, session.tool, panSlop(event.kind));
      } else {
        onPlace(position);
      }
      return;
    }
    if (session.tool == CanvasTool.arrow || session.tool == CanvasTool.shape) {
      _gesture = _DrawingGesture(event.pointer);
      if (session.tool == CanvasTool.arrow) arrow.onPointerDown(event, position);
      if (session.tool == CanvasTool.shape) shape.onPointerDown(event, position);
      return;
    }
    if (event.kind == PointerDeviceKind.touch && !session.touchSelectionEnabled && !spaceHeld) {
      _gesture = _PanGesture(event, event.localPosition, panSlop(event.kind));
      return;
    }
    final touchSelection = event.kind == PointerDeviceKind.touch && session.touchSelectionEnabled;
    if (!touchSelection) onEndEditing();
    final previous = session.selectedIds;
    final toggle = !touchSelection && modifierPressed.value;
    if (!touchSelection && !toggle) session.setSelection(const []);
    if (!touchSelection && event.kind != PointerDeviceKind.mouse) return;
    _gesture = _MarqueeGesture(event.pointer, event.localPosition, panSlop(event.kind), previous, toggle: toggle);
    notifyListeners();
  }

  void pointerMove(PointerMoveEvent event) {
    if (!canHandle(event)) return;
    pointerPosition.value = event.localPosition;
    switch (_gesture) {
      case final _PanGesture pan when pan.pointer == event.pointer:
        pan.velocity.addPosition(event.timeStamp, event.localPosition);
        final displacement = event.localPosition - pan.start;
        if (!pan.started && displacement.distance <= pan.slop) return;
        if (!pan.started) viewport.startPan(pan.start);
        viewport.updatePan(event.localPosition, pan.started ? event.localDelta : displacement);
        pan.started = true;
      case final _PlacementGesture placement when placement.pointer == event.pointer:
        if ((event.localPosition - placement.start).distance > placement.slop) _gesture = null;
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
    final allowed = canHandle(event);
    _pointers.remove(event.pointer);
    _blockedPointers.remove(event.pointer);
    if (!allowed) return;
    final gesture = _gesture;
    if (gesture?.pointer != event.pointer) return;
    switch (gesture) {
      case final _ObjectGesture object:
        // Recognizer callbacks finish this operation explicitly, even after raw release.
        if (!object.transforming && session.editing == null) session.finishOperation();
        return;
      case final _PanGesture pan:
        _gesture = null;
        if (pan.started) {
          pan.velocity.addPosition(event.timeStamp, event.localPosition);
          viewport.endPan(pan.velocity.getVelocity());
        } else if ((event.localPosition - pan.start).distance <= pan.slop) {
          if (pan.secondary) {
            onOpenMenu(pan.menuTarget, event.position);
          } else {
            onEndEditing();
            session.setSelection(const []);
          }
        }
      case final _PlacementGesture placement:
        _gesture = null;
        if (placement.tool == session.tool && (event.localPosition - placement.start).distance <= placement.slop) {
          onPlace(viewport.screenToCanvas(event.localPosition));
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
        if (event.kind == PointerDeviceKind.touch && marquee.end == null) {
          onEndEditing();
          session.setSelection(const []);
        }
      case _EraserGesture():
        _gesture = null;
        session.finishOperation();
      case null:
        break;
    }
    notifyListeners();
  }

  void pointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _blockedPointers.remove(event.pointer);
    if (_gesture?.pointer == event.pointer) {
      _generation++;
      _cancelGesture();
    }
  }

  void hover(PointerHoverEvent event) {
    pointerPosition.value = event.localPosition;
    if (session.tool == CanvasTool.pen && !spaceHeld && !blocked) pen.onPointerHover(event);
  }

  void exit(PointerExitEvent event) {
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

  void _erase(Offset globalPosition) => session.remove(viewport.hitTest(globalPosition));

  void _activate(String id, {bool edit = false}) {
    if (blocked || session.element(id) == null) return;
    if (session.editing?.field == EditorField.markdown) session.editField(null);
    session
      ..promoteAuto([id])
      ..setActive(id);
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
      session.setSelection(before, preserveContext: true);
      selected = true;
    }
    if (_gesture case _ArrowDragGesture(selection: final before) when before.contains(id)) {
      session.setSelection(before, preserveContext: true);
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
    _disposed = true;
    _generation++;
    session.removeListener(_sessionChanged);
    pen.removeListener(notifyListeners);
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
  int _generation = -1;
  final int _contextGeneration;
  bool get attached =>
      _lifetime != null &&
      !input._disposed &&
      _contextGeneration == input._generation &&
      identical(_lifetime, input.session.elementLifetime(id));
  bool get current =>
      attached &&
      !input._disposed &&
      !input.blocked &&
      _generation == input._generation &&
      identical(_lifetime, input.session.elementLifetime(id));

  void pointerDown(PointerDownEvent event, {bool control = false}) {
    if (!attached) return;
    input._observeDown(event);
    if (!input.canHandle(event) || !attached) return;
    _generation = input._generation;
    if (input._gesture case _ObjectGesture(pointer: final pointer, id: final target)
        when pointer == event.pointer && target == id) {
      return;
    }
    if (event.buttons == kSecondaryButton && input.session.tool == CanvasTool.select) {
      input.viewport.stopAnimation();
      input._gesture = _PanGesture(
        event,
        input.viewport.globalToScreen(event.position),
        4,
        menuTarget: id,
        secondary: true,
      );
      return;
    }
    if (event.buttons != kPrimaryButton || input.session.tool != CanvasTool.select) return;
    final session = input.session;
    final value = session.element(id);
    if (value == null) return;
    final selection = session.selectedIds;
    input._gesture = _ObjectGesture(event.pointer, id, selection);
    if (control) {
      if (!input.modifierPressed.value) session.setSelection(const [], preserveContext: true);
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
    if (!session.isSelected(id) && session.activeId != id) session.invalidatePendingEdits();
    if (session.activeId != id && session.editing?.id != id) {
      session.setActive(null);
      input.onEndEditing();
    }
    if (value is! TextElementData || session.editing?.field != EditorField.markdown) {
      if (session.editing?.field == EditorField.markdown) session.editField(null);
    }
    session.setSelection(const [], preserveContext: true);
    if (value is ArrowElementData) {
      input._gesture = _ArrowDragGesture(event.pointer, id, event.position, input.panSlop(event.kind), selection);
    }
  }

  void activate({bool edit = false}) {
    if (!attached || input.blocked || input.modifierPressed.value) return;
    input._activate(id, edit: edit);
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
  }

  void interact() {
    if (!attached || input.blocked) return;
    input.session.promoteAuto([id]);
  }
}
