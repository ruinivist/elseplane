// Owns typed editor snapshots and undo operation grouping.
// Used by EditorSession independently of persistence and Flutter resources.

import 'package:elseplane/canvas/document/canvas_document.dart';

// ---------- Snapshots ----------

enum CanvasTool { select, text, code, media, shape, pen, arrow, eraser }

typedef EditorSnapshot = ({CanvasDocument document, CanvasTool tool, bool touchSelectionEnabled});

// ---------- History ----------

/// Retains the latest fifty completed operations as immutable values.
/// Used by the session without serialization or save timing.
class EditorHistory {
  EditorHistory(this.current);

  static const limit = 50;
  EditorSnapshot current;
  final _undo = <EditorSnapshot>[];
  final _redo = <EditorSnapshot>[];

  void finish(EditorSnapshot next) {
    if (next == current) return;
    _undo.add(current);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
    current = next;
  }

  EditorSnapshot? undo(EditorSnapshot next) {
    finish(next);
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return current = _undo.removeLast();
  }

  EditorSnapshot? redo(EditorSnapshot next) {
    finish(next);
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return current = _redo.removeLast();
  }
}
