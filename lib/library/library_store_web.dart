// Persists library metadata and individual canvas documents in IndexedDB.

import 'dart:async';
import 'dart:js_interop';

import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/library_store_codec.dart';
import 'package:web/web.dart';

class IndexedDbLibraryStore implements LibraryStore {
  // The public parameter name intentionally differs from the private field.
  // ignore: prefer_initializing_formals
  IndexedDbLibraryStore({String databaseName = defaultDatabaseName}) : _databaseName = databaseName;

  static const defaultDatabaseName = 'elseplane.canvas.library';
  static const _schemaVersion = 1;
  static const _metadataStore = 'metadata';
  static const _documentStore = 'documents';
  static const _metadataKey = 'library';

  final String _databaseName;

  @override
  Future<CanvasLibrary?> load() async {
    final database = await _openDatabase();
    try {
      final transaction = database.transaction(
        <JSAny?>[_metadataStore.toJS, _documentStore.toJS].toJS,
        'readonly',
      );
      final completed = _transactionCompletion(transaction);
      final metadataStore = transaction.objectStore(_metadataStore);
      final metadataRequest = metadataStore.get(_metadataKey.toJS);
      final metadataCountRequest = metadataStore.count();
      final keysRequest = transaction.objectStore(_documentStore).getAllKeys();
      final documentsRequest = transaction.objectStore(_documentStore).getAll();
      try {
        final values = await Future.wait<Object?>([
          _requestResult(metadataRequest, transaction),
          _requestResult(metadataCountRequest, transaction),
          _requestResult(keysRequest, transaction),
          _requestResult(documentsRequest, transaction),
        ], eagerError: true);
        await completed;
        final metadata = values[0];
        final metadataCount = values[1];
        if (metadataCount != 0 && metadataCount != 1) throw const FormatException('Invalid library metadata record');
        final keys = _stringList(values[2], 'canvas document keys');
        final documents = _stringList(values[3], 'canvas documents');
        if (keys.length != documents.length) throw const FormatException('Invalid canvas document records');
        if (metadataCount == 0) {
          if (keys.isNotEmpty) throw const FormatException('Canvas documents exist without library metadata');
          return null;
        }
        if (metadata is! String) throw const FormatException('Invalid library metadata record');
        return LibraryStoreCodec.decodeRecords(
          metadata,
          {for (var index = 0; index < keys.length; index++) keys[index]: documents[index]},
        );
      } on Object catch (error, stackTrace) {
        await _ignoreTransactionFailure(completed);
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      database.close();
    }
  }

  @override
  Future<void> save(CanvasLibrary next, {required CanvasLibrary? previous}) async {
    final writes = LibraryStoreCodec.calculateWrites(previous, next);
    if (writes.isEmpty) return;
    final previousMetadata = previous != null && writes.metadata != null
        ? LibraryStoreCodec.encodeMetadata(previous)
        : null;

    final database = await _openDatabase();
    try {
      final storeNames = <JSAny?>[
        if (writes.metadata != null) _metadataStore.toJS,
        if (writes.documentPuts.isNotEmpty || writes.documentDeletes.isNotEmpty) _documentStore.toJS,
      ];
      final transaction = database.transaction(storeNames.toJS, 'readwrite');
      final completed = _transactionCompletion(transaction);
      try {
        final metadata = writes.metadata == null ? null : transaction.objectStore(_metadataStore);
        final documents = writes.documentPuts.isEmpty && writes.documentDeletes.isEmpty
            ? null
            : transaction.objectStore(_documentStore);

        // IndexedDB runs requests in order; a failed check aborts the queued writes.
        if (previous == null) {
          _requireResult(transaction, metadata!.count(), 0, 'Library already exists');
          _requireResult(transaction, documents!.count(), 0, 'Orphaned canvas documents exist');
        } else {
          if (metadata != null) {
            _requireResult(
              transaction,
              metadata.get(_metadataKey.toJS),
              previousMetadata,
              'Library metadata changed in another tab',
            );
          }
          if (documents != null) {
            final previousCanvases = {
              for (final file in previous.files)
                if (!file.isFolder) file.id,
            };
            for (final id in writes.documentPuts.keys) {
              _requireResult(
                transaction,
                documents.count(id.toJS),
                previousCanvases.contains(id) ? 1 : 0,
                'Stale canvas record: $id',
              );
            }
            for (final id in writes.documentDeletes) {
              _requireResult(transaction, documents.count(id.toJS), 1, 'Stale canvas record: $id');
            }
          }
        }

        if (writes.metadata case final value?) {
          metadata!.put(value.toJS, _metadataKey.toJS);
        }
        if (documents != null) {
          for (final entry in writes.documentPuts.entries) {
            documents.put(entry.value.toJS, entry.key.toJS);
          }
          for (final id in writes.documentDeletes) {
            documents.delete(id.toJS);
          }
        }
      } on Object catch (error) {
        _abort(transaction, error);
      }
      await completed;
    } finally {
      database.close();
    }
  }

  Future<IDBDatabase> _openDatabase() {
    final request = window.indexedDB.open(_databaseName, _schemaVersion);
    final result = Completer<IDBDatabase>();
    request.onupgradeneeded = ((Event _) {
      final database = request.result! as IDBDatabase;
      if (!database.objectStoreNames.contains(_metadataStore)) database.createObjectStore(_metadataStore);
      if (!database.objectStoreNames.contains(_documentStore)) database.createObjectStore(_documentStore);
    }).toJS;
    request.onsuccess = ((Event _) {
      if (!result.isCompleted) result.complete(request.result! as IDBDatabase);
    }).toJS;
    request.onerror = ((Event _) {
      if (!result.isCompleted) result.completeError(_requestError(request));
    }).toJS;
    return result.future;
  }
}

void _requireResult(IDBTransaction transaction, IDBRequest request, Object? expected, String message) {
  request.onsuccess = ((Event _) {
    try {
      if (request.result.dartify() != expected) {
        _abort(transaction, StateError(message));
      }
    } on Object catch (error) {
      _abort(transaction, error);
    }
  }).toJS;
}

Future<Object?> _requestResult(IDBRequest request, IDBTransaction transaction) {
  final result = Completer<Object?>();
  request.onsuccess = ((Event _) {
    if (!result.isCompleted) result.complete(request.result.dartify());
  }).toJS;
  request.onerror = ((Event _) {
    final error = _requestError(request);
    if (!result.isCompleted) result.completeError(error);
    _abort(transaction, error);
  }).toJS;
  return result.future;
}

Future<void> _transactionCompletion(IDBTransaction transaction) {
  final result = Completer<void>();
  transaction.oncomplete = ((Event _) {
    _transactionFailures.remove(transaction);
    if (!result.isCompleted) result.complete();
  }).toJS;
  transaction.onabort = ((Event _) {
    final failure = _transactionFailures.remove(transaction);
    if (!result.isCompleted) {
      result.completeError(failure ?? transaction.error ?? StateError('IndexedDB transaction aborted'));
    }
  }).toJS;
  return result.future;
}

void _abort(IDBTransaction transaction, Object failure) {
  _transactionFailures.putIfAbsent(transaction, () => failure);
  try {
    transaction.abort();
  } on Object catch (_) {}
}

final _transactionFailures = <IDBTransaction, Object>{};

Object _requestError(IDBRequest request) => request.error ?? StateError('IndexedDB request failed');

List<String> _stringList(Object? value, String field) {
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('Invalid $field');
  }
  return value.cast<String>();
}

Future<void> _ignoreTransactionFailure(Future<void> transaction) async {
  try {
    await transaction;
  } on Object catch (_) {}
}
