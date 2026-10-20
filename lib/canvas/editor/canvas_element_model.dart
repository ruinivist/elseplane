// Defines the shared mutable model contract for canvas elements.
// Extended by each interactive element tool and renderer.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:flutter/material.dart';

// ---------- Model contract ----------

/// Adds selection and canvas geometry behavior to persisted element data.
/// Extended by each concrete interactive canvas element model.
abstract class CanvasElementModel<T extends CanvasElementData> extends ChangeNotifier {
  // ---------- Construction ----------

  CanvasElementModel(T data) : _data = data;

  // ---------- State ----------

  T _data;
  T get data => _data;
  int _asyncEditGeneration = 0;
  int get asyncEditGeneration => _asyncEditGeneration;

  void invalidatePendingEdits() => _asyncEditGeneration++;
  final ValueNotifier<int> _documentRevision = ValueNotifier(0);
  bool _selected = false;
  bool _active = false;

  Listenable get documentChanges => _documentRevision;

  /// Restores persisted state without recording a document edit.
  void restoreData(covariant T snapshot) {
    if (snapshot.id != data.id || snapshot.runtimeType != data.runtimeType) {
      throw ArgumentError('Restoration must preserve element identity and type');
    }
    invalidatePendingEdits();
    final previous = _data;
    _data = snapshot;
    synchronizeRestoredData(previous);
    notifyListeners();
  }

  @protected
  void synchronizeRestoredData(T previous) {}

  @protected
  void replaceData(T next, {bool rebuild = true, VoidCallback? synchronize}) {
    if (next.id != data.id || next.runtimeType != data.runtimeType) {
      throw ArgumentError('Edits must preserve element identity and type');
    }
    _data = next;
    synchronize?.call();
    _documentRevision.value++;
    if (rebuild) notifyListeners();
  }

  bool get autoArrange => data.autoArrange;

  set autoArrange(bool value) {
    if (data.autoArrange == value) return;
    replaceData(data.copyWith(autoArrange: value) as T);
  }

  bool get selected => _selected;

  set selected(bool value) {
    if (_selected == value) return;
    _selected = value;
    notifyListeners();
  }

  bool get active => _active;

  set active(bool value) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }

  // ---------- Geometry ----------

  Offset get canvasPosition;

  Size get canvasSize;

  void moveBy(Offset delta);

  @override
  void dispose() {
    invalidatePendingEdits();
    _documentRevision.dispose();
    super.dispose();
  }
}

/// Adds center rotation to canvas element models.
/// Floating controls anchor to the element's laid-out render box.
/// Used by elements that share the editor's floating transform controls.
abstract class RotatableCanvasElementModel<T extends CanvasElementData> extends CanvasElementModel<T> {
  RotatableCanvasElementModel(super.data);

  bool get canRotate => true;

  double get rotation;

  void rotate(double angle);
}
