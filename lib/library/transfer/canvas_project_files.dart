// Defines project file picking and saving through the host platform.
// Used by canvas import and export actions.

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ---------- File contract ----------

/// Defines host file operations for portable canvas projects.
/// Used by the canvas page and implemented with the platform file selector.
abstract interface class CanvasProjectFiles {
  Future<Uint8List?> open();

  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType});
}

// ---------- Platform selection ----------

CanvasProjectFiles createCanvasProjectFiles() => _PlatformCanvasProjectFiles();

// ---------- Platform implementation ----------

final class _PlatformCanvasProjectFiles implements CanvasProjectFiles {
  @override
  Future<Uint8List?> open() async => await (await openFile())?.readAsBytes();

  @override
  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType}) async {
    final file = XFile.fromData(bytes, mimeType: mimeType, name: suggestedName);
    if (kIsWeb) {
      await file.saveTo(suggestedName);
      return true;
    }
    final location = await getSaveLocation(
      suggestedName: suggestedName,
    );
    if (location == null) return false;
    await file.saveTo(location.path);
    return true;
  }
}
