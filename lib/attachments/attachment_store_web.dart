// Persists attachment bytes in the browser origin-private file system.
// Selected by app composition for the web workspace.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:web/web.dart';

// ---------- Browser storage ----------

class PlatformAttachmentStore implements AttachmentStore {
  PlatformAttachmentStore({
    Future<FileSystemDirectoryHandle> Function()? rootLookup,
  }) : _rootLookup = rootLookup ?? _lookupRoot;

  final Future<FileSystemDirectoryHandle> Function() _rootLookup;

  // ---------- Public API ----------

  @override
  Future<void> write(String path, Uint8List bytes) async {
    validateAttachmentPath(path);
    validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
    final file = await _file(path, create: true);
    final writable = await file.createWritable().toDart;
    try {
      await writable.write(Uint8List.fromList(bytes).toJS).toDart;
      await writable.close().toDart;
    } on Object catch (_) {
      try {
        await writable.abort().toDart;
      } on Object catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    validateAttachmentPath(path);
    final fileName = path.split('/').last;
    try {
      final parent = await _parentDirectory(path, create: false);
      await parent.removeEntry(fileName).toDart;
    } on Object catch (error) {
      if (_isNotFound(error)) return;
      rethrow;
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    validateAttachmentPath(path);
    final file = await (await _file(path, create: false)).getFile().toDart;
    validateAttachmentSize(file.size, 'Attachment exceeds 10 MiB: $path');
    final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
    validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
    return bytes;
  }

  @override
  Future<Uint8List?> readIfExists(String path) async {
    try {
      return await read(path);
    } on Object catch (error) {
      if (error.isA<DOMException>()) {
        final exception = error as DOMException;
        if (exception.name == 'NotFoundError') return null;
      }
      rethrow;
    }
  }

  // ---------- Private helpers ----------

  Future<FileSystemFileHandle> _file(
    String path, {
    required bool create,
  }) async {
    final fileName = path.split('/').last;
    final parent = await _parentDirectory(path, create: create);
    return await parent.getFileHandle(fileName, FileSystemGetFileOptions(create: create)).toDart;
  }

  Future<FileSystemDirectoryHandle> _parentDirectory(
    String path, {
    required bool create,
  }) async {
    final segments = path.split('/');
    var directory = await _rootLookup();
    for (final segment in segments.take(segments.length - 1)) {
      directory = await directory
          .getDirectoryHandle(
            segment,
            FileSystemGetDirectoryOptions(create: create),
          )
          .toDart;
    }
    return directory;
  }

  static Future<FileSystemDirectoryHandle> _lookupRoot() => window.navigator.storage.getDirectory().toDart;

  static bool _isNotFound(Object error) => error.isA<DOMException>() && (error as DOMException).name == 'NotFoundError';
}
