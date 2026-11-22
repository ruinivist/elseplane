// Verifies IndexedDB library records and transaction failure boundaries.

@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/library_store_codec.dart';
import 'package:elseplane/library/library_store_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart';

void main() {
  final databaseNames = <String>[];

  setUp(databaseNames.clear);
  tearDown(() async {
    for (final name in databaseNames) {
      await _deleteDatabase(name);
    }
  });

  test('loads absent storage and reopens a saved library', () async {
    final name = _newDatabaseName(databaseNames);
    final store = IndexedDbLibraryStore(databaseName: name);
    expect(await store.load(), isNull);

    final library = CanvasLibrary(
      currentId: 'a',
      files: [
        CanvasFile(id: 'a', name: 'A', document: _document(CanvasBackgroundKind.dotGrid)),
        const CanvasFile(id: 'folder', name: 'Folder'),
        CanvasFile(
          id: 'b',
          name: 'B',
          parentId: 'folder',
          document: _document(CanvasBackgroundKind.plain),
        ),
      ],
    );
    await store.save(library, previous: null);

    final restored = (await IndexedDbLibraryStore(databaseName: name).load())!;
    expect(restored.currentId, 'a');
    expect(restored.path('b').map((file) => file.id), ['folder', 'b']);
    expect(restored.file('a').document!.toJson(), library.file('a').document!.toJson());
    expect(restored.file('b').document!.toJson(), library.file('b').document!.toJson());
  });

  test('a document-only save preserves a newer sibling record', () async {
    final name = _newDatabaseName(databaseNames);
    final store = IndexedDbLibraryStore(databaseName: name);
    await store.save(_library(), previous: null);
    final loaded = (await store.load())!;
    final newerSibling = _document(CanvasBackgroundKind.plain);
    await _writeRecords(name, documents: {'b': _encodeDocument(newerSibling)});
    final edited = loaded.replace(CanvasFile(id: 'a', name: 'A', document: _document(CanvasBackgroundKind.plain)));

    await store.save(edited, previous: loaded);

    final restored = (await store.load())!;
    expect(restored.file('a').document!.toJson(), edited.file('a').document!.toJson());
    expect(restored.file('b').document!.toJson(), newerSibling.toJson());
  });

  test('stale structural and document writes cannot create or revive records', () async {
    final name = _newDatabaseName(databaseNames);
    final store = IndexedDbLibraryStore(databaseName: name);
    final previous = _library();
    await store.save(previous, previous: null);
    final loaded = (await store.load())!;

    await _writeRecords(name, metadata: LibraryStoreCodec.encodeMetadata(loaded.select('b')));
    final editedDocument = _document(CanvasBackgroundKind.plain);
    final withNewCanvas = CanvasLibrary(
      currentId: loaded.currentId,
      files: [
        loaded.file('a').copyWith(document: editedDocument),
        loaded.file('b'),
        CanvasFile(id: 'c', name: 'C', document: _document(CanvasBackgroundKind.plain)),
      ],
    );
    await expectLater(store.save(withNewCanvas, previous: loaded), throwsA(anything));
    final afterStructuralFailure = (await store.load())!;
    expect(afterStructuralFailure.currentId, 'b');
    expect(afterStructuralFailure.files.map((file) => file.id), ['a', 'b']);
    expect(afterStructuralFailure.file('a').document!.toJson(), loaded.file('a').document!.toJson());
    expect(await _readRecord(name, 'documents', 'c'), isNull);

    await _writeRecords(name, deleteDocuments: ['a']);
    final edited = loaded.replace(CanvasFile(id: 'a', name: 'A', document: _document(CanvasBackgroundKind.plain)));
    await expectLater(store.save(edited, previous: loaded), throwsA(anything));
    expect(await _readRecord(name, 'documents', 'a'), isNull);
  });

  test('rejects malformed documents and missing records on load', () async {
    final name = _newDatabaseName(databaseNames);
    final store = IndexedDbLibraryStore(databaseName: name);
    await store.save(_library(), previous: null);
    await _writeRecords(name, documents: {'a': 'not JSON'});
    await expectLater(store.load(), throwsFormatException);

    await _writeRecords(name, metadata: 'not JSON', documents: {'a': _encodeDocument(_library().file('a').document!)});
    await expectLater(store.load(), throwsFormatException);

    await _writeRecords(
      name,
      metadata: LibraryStoreCodec.encodeMetadata(_library()),
      documents: {'a': _encodeDocument(_library().file('a').document!)},
      deleteDocuments: ['b'],
    );
    await expectLater(store.load(), throwsFormatException);

    await _writeRecords(name, deleteMetadata: true);
    await expectLater(store.load(), throwsFormatException);
  });

  test('rejects unexpected metadata records on load', () async {
    final unexpectedOnly = _newDatabaseName(databaseNames);
    final store = IndexedDbLibraryStore(databaseName: unexpectedOnly);
    await _writeRecords(unexpectedOnly, metadataRecords: {'unexpected': 'not library metadata'});
    await expectLater(store.load(), throwsFormatException);

    final alongsideExpected = _newDatabaseName(databaseNames);
    await _writeRecords(
      alongsideExpected,
      metadata: LibraryStoreCodec.encodeMetadata(_library()),
      metadataRecords: {'unexpected': 'not library metadata'},
      documents: LibraryStoreCodec.calculateWrites(null, _library()).documentPuts,
    );
    await expectLater(IndexedDbLibraryStore(databaseName: alongsideExpected).load(), throwsFormatException);
  });

  test('first save refuses occupied stores without mutating them', () async {
    final unexpectedMetadata = _newDatabaseName(databaseNames);
    await _writeRecords(unexpectedMetadata, metadataRecords: {'unexpected': 'preserve me'});
    final metadataStore = IndexedDbLibraryStore(databaseName: unexpectedMetadata);
    await expectLater(metadataStore.save(_library(), previous: null), throwsA(anything));
    expect(await _readRecord(unexpectedMetadata, 'metadata', 'unexpected'), 'preserve me');
    expect(await _readRecord(unexpectedMetadata, 'metadata', 'library'), isNull);
    expect(await _readRecord(unexpectedMetadata, 'documents', 'a'), isNull);
    expect(await _readRecord(unexpectedMetadata, 'documents', 'b'), isNull);

    final orphanDocument = _newDatabaseName(databaseNames);
    await _writeRecords(orphanDocument, documents: {'orphan': 'preserve me'});
    final documentStore = IndexedDbLibraryStore(databaseName: orphanDocument);
    await expectLater(documentStore.save(_library(), previous: null), throwsA(anything));
    expect(await _readRecord(orphanDocument, 'metadata', 'library'), isNull);
    expect(await _readRecord(orphanDocument, 'documents', 'orphan'), 'preserve me');
    expect(await _readRecord(orphanDocument, 'documents', 'a'), isNull);
    expect(await _readRecord(orphanDocument, 'documents', 'b'), isNull);
  });

  test('aborted initialization rolls back its earlier metadata put', () async {
    final name = _newDatabaseName(databaseNames);
    await _createDatabase(name, inlineDocumentKey: true);
    final store = IndexedDbLibraryStore(databaseName: name);

    await expectLater(store.save(_library(), previous: null), throwsA(anything));

    expect(await _readRecord(name, 'metadata', 'library'), isNull);
  });
}

String _newDatabaseName(List<String> names) {
  final name = 'elseplane-test-${const Uuid().v4()}';
  names.add(name);
  return name;
}

CanvasLibrary _library() => CanvasLibrary(
  currentId: 'a',
  files: [
    CanvasFile(id: 'a', name: 'A', document: _document(CanvasBackgroundKind.dotGrid)),
    CanvasFile(id: 'b', name: 'B', document: _document(CanvasBackgroundKind.dotGrid)),
  ],
);

CanvasDocument _document(CanvasBackgroundKind background) => CanvasDocument(background: background, elements: []);

String _encodeDocument(CanvasDocument document) => jsonEncode(document.toJson());

Future<IDBDatabase> _openDatabase(String name, {bool inlineDocumentKey = false}) {
  final request = window.indexedDB.open(name, 1);
  final result = Completer<IDBDatabase>();
  request.onupgradeneeded = ((Event _) {
    final database = request.result! as IDBDatabase..createObjectStore('metadata');
    if (inlineDocumentKey) {
      // This forces a document put to fail after the metadata put is queued.
      database.createObjectStore('documents', IDBObjectStoreParameters(keyPath: 'id'.toJS));
    } else {
      database.createObjectStore('documents');
    }
  }).toJS;
  request.onsuccess = ((Event _) {
    if (!result.isCompleted) result.complete(request.result! as IDBDatabase);
  }).toJS;
  request.onerror = ((Event _) {
    if (!result.isCompleted) result.completeError(request.error ?? StateError('Could not open test database'));
  }).toJS;
  return result.future;
}

Future<void> _writeRecords(
  String name, {
  String? metadata,
  bool deleteMetadata = false,
  Map<String, String> metadataRecords = const {},
  Map<String, String> documents = const {},
  List<String> deleteDocuments = const [],
}) async {
  final database = await _openDatabase(name);
  try {
    final transaction = database.transaction(
      <JSAny?>['metadata'.toJS, 'documents'.toJS].toJS,
      'readwrite',
    );
    final completed = _completed(transaction);
    final metadataStore = transaction.objectStore('metadata');
    if (metadata != null) metadataStore.put(metadata.toJS, 'library'.toJS);
    if (deleteMetadata) metadataStore.delete('library'.toJS);
    for (final entry in metadataRecords.entries) {
      metadataStore.put(entry.value.toJS, entry.key.toJS);
    }
    final documentStore = transaction.objectStore('documents');
    for (final entry in documents.entries) {
      documentStore.put(entry.value.toJS, entry.key.toJS);
    }
    for (final id in deleteDocuments) {
      documentStore.delete(id.toJS);
    }
    await completed;
  } finally {
    database.close();
  }
}

Future<Object?> _readRecord(String name, String storeName, String key) async {
  final database = await _openDatabase(name);
  try {
    final transaction = database.transaction(storeName.toJS, 'readonly');
    final completed = _completed(transaction);
    final request = transaction.objectStore(storeName).get(key.toJS);
    final value = Completer<Object?>();
    request.onsuccess = ((Event _) => value.complete(request.result.dartify())).toJS;
    request.onerror = ((Event _) => value.completeError(
      request.error ?? StateError('Could not read test record'),
    )).toJS;
    final result = await value.future;
    await completed;
    return result;
  } finally {
    database.close();
  }
}

Future<void> _createDatabase(String name, {bool inlineDocumentKey = false}) async {
  final database = await _openDatabase(name, inlineDocumentKey: inlineDocumentKey);
  database.close();
}

Future<void> _deleteDatabase(String name) {
  final request = window.indexedDB.deleteDatabase(name);
  final result = Completer<void>();
  request.onsuccess = ((Event _) => result.complete()).toJS;
  request.onerror = ((Event _) => result.completeError(
    request.error ?? StateError('Could not delete test database'),
  )).toJS;
  return result.future;
}

Future<void> _completed(IDBTransaction transaction) {
  final result = Completer<void>();
  transaction.oncomplete = ((Event _) => result.complete()).toJS;
  transaction.onabort = ((Event _) => result.completeError(
    transaction.error ?? StateError('Test transaction aborted'),
  )).toJS;
  return result.future;
}
