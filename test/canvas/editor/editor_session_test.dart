// Checks editor ownership, typed history, and logical context cancellation.
// Exercises session operations without widgets, storage, or browser APIs.

import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/geometry/arrow_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Fixtures ----------

ShapeElementData _shape(String id, {bool auto = false}) => ShapeElementData(
  id: id,
  position: Offset.zero,
  size: const Size(100, 100),
  kind: ShapeKind.rectangle,
  strokeColor: const Color(0xff000000),
  fillColor: null,
  strokeWidth: 2,
  autoArrange: auto,
);

CanvasDocument _document(List<CanvasElementData> elements) =>
    CanvasDocument(background: CanvasBackgroundKind.plain, elements: elements);

EditorSession _session(List<CanvasElementData> elements) {
  final session = EditorSession(_document(elements), initialColor: const Color(0xff000000));
  addTearDown(session.dispose);
  return session;
}

// ---------- Operations and history ----------

void main() {
  test('typed equality compares independently decoded nested values', () {
    final document = _document([
      _shape('shape'),
      TextElementData(
        id: 'text',
        position: Offset.zero,
        width: 200,
        height: null,
        markdown: 'text',
        style: const TextNodeStyle(fontFamily: 'unavailable font'),
      ),
      CodeElementData(
        id: 'code',
        position: Offset.zero,
        size: const Size(300, 300),
        language: CodeLanguage.dart,
        source: 'source',
        title: 'title',
        showLineNumbers: true,
      ),
      MediaElementData(id: 'media', position: Offset.zero, width: 200, url: ''),
      PenElementData(
        id: 'pen',
        position: Offset.zero,
        size: const Size(40, 20),
        hitSlop: 6,
        color: const Color(0xff000000),
        width: 3,
        points: const [PenPointData(Offset.zero, pressure: 0.5)],
      ),
      ArrowElementData(
        id: 'arrow',
        start: Offset.zero,
        controls: const [Offset(50, 40)],
        end: const Offset(100, 0),
        color: const Color(0xff000000),
        strokeStyle: ArrowStrokeStyle.solid,
        strokeWidth: 2,
      ),
    ]);
    final decoded = CanvasDocument.fromJson(document.toJson());
    expect(decoded, document);
    expect(decoded.hashCode, document.hashCode);
    expect(decoded.elements, isNot(same(document.elements)));
    expect(decoded.copyWith(elements: decoded.elements.reversed.toList()), isNot(document));
  });

  test('group moves publish complete immutable snapshots and undo once', () {
    final session = _session([_shape('a', auto: true), _shape('b', auto: true), _shape('c')]);
    final original = session.document;
    final snapshots = <CanvasDocument>[];
    session
      ..documentChanges.addListener(() => snapshots.add(session.document))
      ..move(['a', 'b'], const Offset(10, 5))
      ..move(['a', 'b'], const Offset(20, 10))
      ..finishOperation();
    expect(snapshots, hasLength(2));
    expect(snapshots.first.elements.map((a) => a.id), ['c', 'a', 'b']);
    expect((snapshots.first.elements.last as ShapeElementData).position, const Offset(10, 5));
    expect((original.elements.first as ShapeElementData).position, Offset.zero);
    session.undo();
    expect(session.document, original);
    session.redo();
    expect(session.document, snapshots[1]);
  });

  test('no-ops including net-zero operations preserve redo', () {
    final session = _session([_shape('a')])
      ..move(['a'], const Offset(10, 0))
      ..finishOperation()
      ..undo()
      ..move(['a'], Offset.zero)
      ..move(['a'], const Offset(4, 0))
      ..move(['a'], const Offset(-4, 0))
      ..finishOperation()
      ..redo();
    expect((session.document.elements.single as ShapeElementData).position, const Offset(10, 0));
  });

  test('tool-only history preserves selection without document publication', () {
    final session = _session([_shape('a')]);
    var writes = 0;
    session
      ..documentChanges.addListener(() => writes++)
      ..setSelection(['a'])
      ..chooseTool(CanvasTool.pen)
      ..undo();
    expect(session.tool, CanvasTool.select);
    expect(session.selectedIds, {'a'});
    session.redo();
    expect(session.tool, CanvasTool.pen);
    expect(writes, 0);
  });

  test('placement and automatic Select transition share one operation', () {
    final session = _session([])
      ..chooseTool(CanvasTool.shape)
      ..insert([_shape('new')], returnToSelect: true)
      ..undo();
    expect(session.document.elements, isEmpty);
    expect(session.tool, CanvasTool.shape);
    session.undo();
    expect(session.tool, CanvasTool.select);
    session
      ..redo()
      ..redo();
    expect(session.document.elements.single.id, 'new');
    expect(session.tool, CanvasTool.select);
  });

  test('source and title are separate content groups and paste contexts', () {
    final session = _session([
      CodeElementData(
        id: 'code',
        position: Offset.zero,
        size: const Size(300, 300),
        language: CodeLanguage.dart,
        source: '',
        title: '',
        showLineNumbers: true,
      ),
    ]);
    final token = (session..editField((id: 'code', field: EditorField.source))).captureEdit('code');
    session
      ..setCodeSource('code', 'one')
      ..editField((id: 'code', field: EditorField.source))
      ..setCodeSource('code', 'two');
    expect(token.isCurrent, isTrue);
    session.editField((id: 'code', field: EditorField.title));
    expect(token.isCurrent, isFalse);
    session
      ..setCodeTitle('code', 'title')
      ..editField(null)
      ..undo();
    final afterTitle = session.document.elements.single as CodeElementData;
    expect(afterTitle.source, 'two');
    expect(afterTitle.title, '');
    session.undo();
    expect((session.document.elements.single as CodeElementData).source, '');
  });

  test('invalid group edits and orders fail atomically without consuming redo', () {
    final session = _session([_shape('a'), _shape('b')]);
    final original = session.document;
    expect(() => session.move(['a', 'b'], const Offset(double.infinity, 0)), throwsFormatException);
    expect(() => session.arrange(['a'], ['a', 'a']), throwsArgumentError);
    expect(() => session.insert([_shape('a')]), throwsArgumentError);
    expect(session.document, same(original));
    expect(() => session.move(['missing'], const Offset(1, 0)), throwsArgumentError);
    expect(() => session.editField((id: 'a', field: EditorField.source)), throwsArgumentError);
    expect(() => session.setAutoArrange(['missing'], value: true), throwsArgumentError);
    expect(session.editing, isNull);
  });

  for (final order in <List<String>?>[
    null,
    ['a', 'b'],
  ]) {
    test('unchanged arrangement $order preserves Auto, publication, and redo', () {
      final session = _session([_shape('a', auto: true), _shape('b')])
        ..move(['b'], const Offset(10, 0))
        ..finishOperation();
      final moved = session.document;
      session.undo();
      final original = session.document;
      var publications = 0;
      session.documentChanges.addListener(() => publications++);
      session
        ..arrange(['a', 'b'], order)
        ..finishOperation();
      expect(session.document, same(original));
      expect(session.document.elements.first.autoArrange, isTrue);
      expect(publications, 0);
      session.redo();
      expect(session.document, moved);
    });
  }

  test('history retains fifty operations and new choices clear redo', () {
    final session = _session([_shape('a')]);
    for (var index = 0; index < 55; index++) {
      session
        ..move(['a'], const Offset(1, 0))
        ..finishOperation();
    }
    for (var index = 0; index < 55; index++) {
      session.undo();
    }
    expect((session.document.elements.single as ShapeElementData).position, const Offset(5, 0));
    session
      ..chooseTool(CanvasTool.pen)
      ..redo();
    expect(session.tool, CanvasTool.pen);
  });

  test('removal, restore, and disposal invalidate captured edits', () {
    final session = _session([_shape('a')]);
    final pending = session.captureEdit('a');
    final lifetime = session.elementLifetime('a');
    session.remove(['a']);
    expect(pending.isCurrent, isFalse);
    session
      ..finishOperation()
      ..undo();
    expect(session.elementLifetime('a'), isNot(same(lifetime)));
    expect(pending.isCurrent, isFalse);
    final restored = session.captureEdit('a');
    session.endLifetime();
    expect(restored.isCurrent, isFalse);
    session.move(['a'], const Offset(100, 0));
    expect((session.document.elements.single as ShapeElementData).position, Offset.zero);
  });

  test('pen movement preserves normalized local geometry', () {
    final session = _session([
      PenElementData(
        id: 'pen',
        position: const Offset(10, 20),
        size: const Size(61, 61),
        hitSlop: 3,
        color: const Color(0xff000000),
        width: 2.5,
        points: const [
          PenPointData(Offset(5.5, 5.5), pressure: 0.5),
        ],
      ),
    ])..move(['pen'], const Offset(8, -4));
    final pen = session.element('pen')! as PenElementData;

    expect(pen.position, const Offset(18, 16));
    expect(pen.size, const Size(61, 61));
    expect(pen.points.single.position.dx, 5.5);
  });

  test('arrow movement shifts every durable point equally', () {
    final session = _session([
      ArrowElementData(
        id: 'arrow',
        start: Offset.zero,
        controls: const [Offset(20, -8)],
        end: const Offset(40, 10),
        color: const Color(0xff000000),
        strokeStyle: ArrowStrokeStyle.solid,
        strokeWidth: 2,
      ),
    ]);
    final before = (session.element('arrow')! as ArrowElementData).geometry;

    session.move(['arrow'], const Offset(12, 7));
    final arrow = session.element('arrow')! as ArrowElementData;

    expect(arrow.geometry.start, before.start + const Offset(12, 7));
    expect(arrow.geometry.controls.single, before.controls.single + const Offset(12, 7));
    expect(arrow.geometry.end, before.end + const Offset(12, 7));
  });
}
