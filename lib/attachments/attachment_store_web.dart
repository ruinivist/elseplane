// Persists attachment bytes in the browser origin-private file system.
// Selected by app composition for the web workspace.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:web/web.dart';

// ---------- Browser storage ----------

class PlatformAttachmentStore implements AttachmentStore {
  // ---------- Public API ----------

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final file = await _file(path, create: true);
    final writable = await file.createWritable().toDart;
    await writable.write(bytes.toJS).toDart;
    await writable.close().toDart;
  }

  @override
  Future<void> delete(String path) async {
    final fileName = attachmentFileName(path);
    try {
      final root = await window.navigator.storage.getDirectory().toDart;
      final attachments = await root.getDirectoryHandle('attachments').toDart;
      await attachments.removeEntry(fileName).toDart;
    } catch (error) {
      if (error.isA<DOMException>() && (error as DOMException).name == 'NotFoundError') return;
      rethrow;
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    final file = await (await _file(path, create: false)).getFile().toDart;
    return (await file.arrayBuffer().toDart).toDart.asUint8List();
  }

  @override
  Future<Uint8List?> readIfExists(String path) async {
    try {
      return await read(path);
    } catch (error) {
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
    final fileName = attachmentFileName(path);
    final root = await window.navigator.storage.getDirectory().toDart;
    final attachments = await root
        .getDirectoryHandle(
          'attachments',
          FileSystemGetDirectoryOptions(create: create),
        )
        .toDart;
    return await attachments
        .getFileHandle(
          fileName,
          FileSystemGetFileOptions(create: create),
        )
        .toDart;
  }
}
