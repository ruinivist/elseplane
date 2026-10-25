// Synchronizes retained rendering resources with accepted editor snapshots.
// Owned by CanvasView outside lazily culled element widgets.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:flutter/material.dart';

// ---------- Presentation adapter ----------

abstract class ElementResources<T extends CanvasElementData> extends ChangeNotifier {
  ElementResources(this.session, T data)
    : _data = data,
      _restoration = session.restorationGeneration,
      _targetLifetime = session.elementLifetime(data.id) {
    session.addListener(_synchronize);
  }

  final EditorSession session;
  T _data;
  final Object? _targetLifetime;
  int _restoration;
  bool _disposed = false;
  bool _detached = false;
  bool get disposed => _disposed;
  T get data => _data;
  bool get selected => attached && session.isSelected(data.id);
  bool get active => attached && session.activeId == data.id;
  bool get autoArrange => data.autoArrange;
  bool get attached =>
      _targetLifetime != null &&
      !disposed &&
      !_detached &&
      session.isLive &&
      identical(_targetLifetime, session.elementLifetime(data.id));

  void _synchronize() {
    if (!attached) {
      detach();
      return;
    }
    final next = session.element(data.id);
    if (next is! T || next.runtimeType != data.runtimeType) return;
    final previous = _data;
    _data = next;
    final restored = _restoration != session.restorationGeneration;
    _restoration = session.restorationGeneration;
    synchronizeData(previous, restored: restored);
    notifyListeners();
  }

  @protected
  void synchronizeData(T previous, {required bool restored}) {}

  Offset get canvasPosition;
  Size get canvasSize;

  void detach() {
    _detached = true;
  }

  @override
  void dispose() {
    detach();
    _disposed = true;
    session.removeListener(_synchronize);
    super.dispose();
  }
}
