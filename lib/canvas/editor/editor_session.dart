// Owns the open document, interaction state, and accepted edit operations.
// Used by Workspace for durability and canvas presentation for edit requests.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_history.dart';
import 'package:elseplane/canvas/geometry/element_geometry.dart';
import 'package:flutter/foundation.dart';

export 'editor_history.dart' show CanvasTool;

// ---------- Context and defaults ----------

enum EditorField { markdown, source, title, mediaUrl }

typedef EditorContext = ({String id, EditorField field});

typedef DrawingDefaults = ({
  Color color,
  double width,
  double streamline,
  ShapeKind shapeKind,
  Color shapeColor,
  Color? shapeFill,
  double shapeWidth,
  Color arrowColor,
  ArrowStrokeStyle arrowStyle,
  double arrowWidth,
});

extension DrawingDefaultsChanges on DrawingDefaults {
  DrawingDefaults copyWith({
    Color? color,
    double? width,
    double? streamline,
    ShapeKind? shapeKind,
    Color? shapeColor,
    Color? shapeFill,
    bool clearShapeFill = false,
    double? shapeWidth,
    Color? arrowColor,
    ArrowStrokeStyle? arrowStyle,
    double? arrowWidth,
  }) => (
    color: color ?? this.color,
    width: width ?? this.width,
    streamline: streamline ?? this.streamline,
    shapeKind: shapeKind ?? this.shapeKind,
    shapeColor: shapeColor ?? this.shapeColor,
    shapeFill: clearShapeFill ? null : shapeFill ?? this.shapeFill,
    shapeWidth: shapeWidth ?? this.shapeWidth,
    arrowColor: arrowColor ?? this.arrowColor,
    arrowStyle: arrowStyle ?? this.arrowStyle,
    arrowWidth: arrowWidth ?? this.arrowWidth,
  );
}

/// Checks whether async work still belongs to its original editor and target.
/// Used before applying clipboard reads, uploads, and their error messages.
class EditorEditToken {
  EditorEditToken._(this._session, this._generation, this._id)
    : _targetLifetime = _id == null ? null : _session.elementLifetime(_id);
  final EditorSession _session;
  final int _generation;
  final String? _id;
  final Object? _targetLifetime;
  bool get isCurrent =>
      _session.isLive &&
      _generation == _session.editGeneration &&
      (_id == null || _targetLifetime != null && identical(_targetLifetime, _session.elementLifetime(_id)));
}

// ---------- Session ----------

/// Coordinates edits and interaction state for one open canvas.
/// Owned by Workspace and observed by canvas presentation.
class EditorSession extends ChangeNotifier {
  // ---------- Construction ----------

  EditorSession(CanvasDocument document, {required Color initialColor, DrawingDefaults? defaults})
    : _defaults =
          defaults ??
          (
            color: initialColor,
            width: 4,
            streamline: penStreamlineDefault,
            shapeKind: ShapeKind.roundedRectangle,
            shapeColor: initialColor,
            shapeFill: null,
            shapeWidth: 2,
            arrowColor: initialColor,
            arrowStyle: ArrowStrokeStyle.solid,
            arrowWidth: 2,
          ),
      _document = document {
    _validateDocument(document);
    _byId = {for (final value in document.elements) value.id: value};
    _lifetimes = {for (final id in _byId.keys) id: Object()};
    _history = EditorHistory(_snapshot);
  }

  // ---------- State ----------

  CanvasDocument _document;
  late Map<String, CanvasElementData> _byId;
  late Map<String, Object> _lifetimes;
  late final EditorHistory _history;
  final _documentChanges = ChangeNotifier();
  final _selectedIds = <String>{};
  String? _activeId;
  EditorContext? _editing;
  CanvasTool _tool = CanvasTool.select;
  bool _touchSelectionEnabled = false;
  bool _live = true;
  int _editGeneration = 0;
  int _restorationGeneration = 0;
  DrawingDefaults _defaults;
  DrawingDefaults get defaults => _defaults;
  CanvasDocument get document => _document;
  Listenable get documentChanges => _documentChanges;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool isSelected(String id) => _selectedIds.contains(id);
  String? get activeId => _activeId;
  EditorContext? get editing => _editing;
  CanvasTool get tool => _tool;
  bool get touchSelectionEnabled => _touchSelectionEnabled;
  bool get isLive => _live;
  int get editGeneration => _editGeneration;
  int get restorationGeneration => _restorationGeneration;
  EditorSnapshot get _snapshot => (document: document, tool: tool, touchSelectionEnabled: touchSelectionEnabled);

  CanvasElementData? element(String id) => _byId[id];
  Object? elementLifetime(String id) => _lifetimes[id];

  void setDrawingDefaults(DrawingDefaults value) {
    if (!_live || value == _defaults) return;
    _defaults = value;
    notifyListeners();
  }

  // ---------- Interaction state and history ----------

  EditorEditToken captureEdit([String? id]) => EditorEditToken._(this, editGeneration, id);
  void invalidatePendingEdits() => _editGeneration++;

  void setSelection(Iterable<String> ids, {bool preserveContext = false}) {
    if (!_live) return;
    final next = ids.toSet();
    if (setEquals(next, _selectedIds)) return;
    if (next.any((id) => element(id) == null)) throw ArgumentError('Unknown selected element');
    if (!preserveContext) invalidatePendingEdits();
    _selectedIds
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void setActive(String? id) {
    if (!_live) return;
    if (id != null && element(id) == null) throw ArgumentError('Unknown active element');
    if (_activeId == id) return;
    if (_editing != null && _editing!.id != id) {
      finishOperation();
      _editing = null;
    }
    invalidatePendingEdits();
    _activeId = id;
    notifyListeners();
  }

  void editField(EditorContext? value) {
    if (!_live) return;
    if (value == _editing) return;
    if (value != null) {
      final target = element(value.id);
      final valid = switch (value.field) {
        EditorField.markdown => target is TextElementData,
        EditorField.source || EditorField.title => target is CodeElementData,
        EditorField.mediaUrl => target is MediaElementData,
      };
      if (!valid) throw ArgumentError('Unknown editing field');
    }
    finishOperation();
    invalidatePendingEdits();
    _editing = value;
    notifyListeners();
  }

  void chooseTool(CanvasTool value, {bool touchSelectionEnabled = false}) {
    if (!_live) return;
    finishOperation();
    _applyTool(value, touchSelectionEnabled: touchSelectionEnabled);
    finishOperation();
  }

  void _applyTool(CanvasTool value, {bool touchSelectionEnabled = false}) {
    invalidatePendingEdits();
    _editing = null;
    _activeId = null;
    _tool = value;
    _touchSelectionEnabled = touchSelectionEnabled;
    notifyListeners();
  }

  void finishOperation() {
    if (_live) _history.finish(_snapshot);
  }

  void undo() => _restore(_history.undo(_snapshot));
  void redo() => _restore(_history.redo(_snapshot));

  void _restore(EditorSnapshot? snapshot) {
    if (!_live || snapshot == null) return;
    final changed = document != snapshot.document;
    invalidatePendingEdits();
    _restorationGeneration++;
    _activeId = null;
    _editing = null;
    _tool = snapshot.tool;
    _touchSelectionEnabled = snapshot.touchSelectionEnabled;
    if (changed) _selectedIds.clear();
    _setDocument(snapshot.document);
    notifyListeners();
    if (changed) _documentChanges.notifyListeners();
  }

  // ---------- Document operations ----------

  void insert(List<CanvasElementData> values, {bool returnToSelect = false}) {
    if (!_live || values.isEmpty) return;
    final next = document.copyWith(elements: [...document.elements, ...values]);
    _validateDocument(next);
    finishOperation();
    if (returnToSelect) {
      _tool = CanvasTool.select;
      _touchSelectionEnabled = false;
    }
    _publish(next);
    finishOperation();
  }

  void remove(Iterable<String> ids) {
    if (!_live) return;
    final removed = ids.toSet();
    if (!document.elements.any((value) => removed.contains(value.id))) return;
    invalidatePendingEdits();
    _selectedIds.removeAll(removed);
    if (removed.contains(_activeId)) _activeId = null;
    if (removed.contains(_editing?.id)) _editing = null;
    _publish(document.copyWith(elements: document.elements.where((value) => !removed.contains(value.id)).toList()));
  }

  void setBackground(CanvasBackgroundKind value) => _publish(document.copyWith(background: value));

  void move(Iterable<String> ids, Offset delta) {
    if (delta == Offset.zero) return;
    _change(ids, (value) => moveElement(value, delta), promote: true);
  }

  void resizeText(String id, Size renderedSize, Offset delta) =>
      _change([id], (value) => resizeTextElement(value as TextElementData, renderedSize, delta), promote: true);

  void resizeCode(String id, Size size) =>
      _change([id], (value) => resizeCodeElement(value as CodeElementData, size), promote: true);

  void resizeMedia(String id, Offset delta, double aspectRatio) =>
      _change([id], (value) => resizeMediaElement(value as MediaElementData, delta, aspectRatio), promote: true);

  void resizeShape(String id, Offset delta) =>
      _change([id], (value) => resizeShapeElement(value as ShapeElementData, delta), promote: true);

  void rotate(String id, double angle) => _change(
    [id],
    (value) => switch (value) {
      final TextElementData a => a.copyWith(rotation: angle),
      final CodeElementData a => a.copyWith(rotation: angle),
      final MediaElementData a => a.copyWith(rotation: angle),
      _ => throw ArgumentError('Element does not support rotation'),
    },
    promote: true,
  );

  void setArrowPoint(String id, int index, Offset position) =>
      _change([id], (value) => moveArrowPoint(value as ArrowElementData, index, position), promote: true);

  void setMarkdown(String id, String markdown) =>
      _change([id], (a) => (a as TextElementData).copyWith(markdown: markdown), promote: true);
  void setTextStyle(String id, TextNodeStyle style) =>
      _change([id], (a) => (a as TextElementData).copyWith(style: style));
  void setCodeSource(String id, String source) =>
      _change([id], (a) => (a as CodeElementData).copyWith(source: source), promote: true);
  void setCodeTitle(String id, String title) =>
      _change([id], (a) => (a as CodeElementData).copyWith(title: title), promote: true);
  void setCodeLanguage(String id, CodeLanguage language) =>
      _change([id], (a) => (a as CodeElementData).copyWith(language: language));
  void setCodeBackground(String id, BlockBackgroundKind background) =>
      _change([id], (a) => (a as CodeElementData).copyWith(background: background));
  void setLineNumbers(String id, {required bool value}) =>
      _change([id], (a) => (a as CodeElementData).copyWith(showLineNumbers: value));
  void setMediaUrl(String id, String url) =>
      _change([id], (a) => (a as MediaElementData).copyWith(url: url), promote: true);
  void setShapeOptions(
    String id, {
    ShapeKind? kind,
    Color? strokeColor,
    Color? fillColor,
    bool clearFillColor = false,
    double? strokeWidth,
  }) => _change(
    [id],
    (a) => (a as ShapeElementData).copyWith(
      kind: kind,
      strokeColor: strokeColor,
      fillColor: fillColor,
      clearFillColor: clearFillColor,
      strokeWidth: strokeWidth,
    ),
  );
  void setArrowOptions(String id, {Color? color, ArrowStrokeStyle? strokeStyle, double? strokeWidth}) => _change([
    id,
  ], (a) => (a as ArrowElementData).copyWith(color: color, strokeStyle: strokeStyle, strokeWidth: strokeWidth));

  // ---------- Ordering ----------

  void promoteAuto(Iterable<String> ids) {
    final targets = ids.toSet();
    final promoted = document.elements.where((a) => targets.contains(a.id) && a.autoArrange).toList();
    if (promoted.isEmpty) return;
    final promotedIds = promoted.map((a) => a.id).toSet();
    _publish(
      document.copyWith(elements: [...document.elements.where((a) => !promotedIds.contains(a.id)), ...promoted]),
    );
  }

  void arrange(Iterable<String> ids, List<String>? proposedOrder) {
    final targets = ids.toSet();
    final byId = {for (final a in document.elements) a.id: a};
    if (targets.any((id) => !byId.containsKey(id))) throw ArgumentError('Unknown arrangement target');
    final order = proposedOrder ?? byId.keys.toList();
    if (order.length != byId.length ||
        order.toSet().length != byId.length ||
        order.any((id) => !byId.containsKey(id))) {
      throw ArgumentError('Expected every document ID once');
    }
    if (listEquals(order, byId.keys.toList())) return;
    _publish(
      document.copyWith(
        elements: [
          for (final id in order)
            if (targets.contains(id)) byId[id]!.copyWith(autoArrange: false) else byId[id]!,
        ],
      ),
    );
  }

  void setAutoArrange(Iterable<String> ids, {required bool value}) {
    final targets = ids.toSet();
    if (targets.any((id) => element(id) == null)) throw ArgumentError('Unknown arrangement target');
    final next = [
      for (final a in document.elements)
        if (targets.contains(a.id)) a.copyWith(autoArrange: value) else a,
    ];
    final promoted = value ? next.where((a) => targets.contains(a.id)).toList() : <CanvasElementData>[];
    _publish(document.copyWith(elements: value ? [...next.where((a) => !targets.contains(a.id)), ...promoted] : next));
  }

  // ---------- Publication and lifetime ----------

  void _change(Iterable<String> ids, CanvasElementData Function(CanvasElementData) change, {bool promote = false}) {
    if (!_live) return;
    final targets = ids.toSet();
    if (targets.any((id) => element(id) == null)) throw ArgumentError('Unknown element');
    var changed = false;
    final values = <CanvasElementData>[];
    for (final current in document.elements) {
      if (!targets.contains(current.id)) {
        values.add(current);
        continue;
      }
      final next = change(current);
      if (next.id != current.id || next.runtimeType != current.runtimeType) {
        throw ArgumentError('An edit must preserve identity');
      }
      next.validate();
      changed |= next != current;
      values.add(next == current ? current : next);
    }
    if (!changed) return;
    final enabled = promote
        ? values.where((a) => targets.contains(a.id) && a.autoArrange).map((a) => a.id).toSet()
        : <String>{};
    _publish(
      document.copyWith(
        elements: [...values.where((a) => !enabled.contains(a.id)), ...values.where((a) => enabled.contains(a.id))],
      ),
    );
  }

  void _publish(CanvasDocument next) {
    if (!_live || next == document) return;
    _setDocument(next);
    notifyListeners();
    _documentChanges.notifyListeners();
  }

  void _setDocument(CanvasDocument next) {
    _lifetimes = {
      for (final value in next.elements)
        value.id: _byId[value.id]?.runtimeType == value.runtimeType ? _lifetimes[value.id]! : Object(),
    };
    _byId = {for (final value in next.elements) value.id: value};
    _document = next;
  }

  static void _validateDocument(CanvasDocument document) {
    final ids = <String>{};
    for (final a in document.elements) {
      if (!ids.add(a.id)) throw ArgumentError('Duplicate element ID');
      a.validate();
    }
  }

  void endLifetime() {
    if (!_live) return;
    invalidatePendingEdits();
    _restorationGeneration++;
    _live = false;
  }

  @override
  void dispose() {
    endLifetime();
    _documentChanges.dispose();
    super.dispose();
  }
}
