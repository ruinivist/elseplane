// Defines project file picking and saving through the host platform.
// Used by canvas import and export actions.

import 'dart:typed_data';

import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ---------- File contract ----------

/// Defines host file operations for portable canvas projects.
/// Used by the canvas page and implemented with the platform file selector.
abstract interface class CanvasProjectFiles {
  Future<({String name, Uint8List bytes})?> open();

  Future<bool> save(Uint8List bytes, {required String suggestedName, required String mimeType});
}

// ---------- Platform selection ----------

CanvasProjectFiles createCanvasProjectFiles() => _PlatformCanvasProjectFiles();

// ---------- Platform implementation ----------

final class _PlatformCanvasProjectFiles implements CanvasProjectFiles {
  @override
  Future<({String name, Uint8List bytes})?> open() async {
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Canvas transfer', extensions: ['canvas.json', 'zip']),
      ],
    );
    if (selected == null) return null;
    final name = selected.name;
    if (!name.endsWith('.canvas.json') && !name.endsWith('.zip')) {
      throw const FormatException('Unsupported transfer file');
    }
    validateCanvasTransferSize(await selected.length());
    final bytes = await selected.readAsBytes();
    validateCanvasTransferSize(bytes.length);
    return (name: name, bytes: bytes);
  }

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
