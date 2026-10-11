// Defines attachment storage operations and shared path handling.
// Used by platform stores, media nodes, and project transfer flows.

import 'dart:typed_data';

// ---------- Limits ----------

const int attachmentMaximumBytes = 10 * 1024 * 1024;

void validateAttachmentSize(int byteLength, String errorMessage) {
  if (byteLength > attachmentMaximumBytes) {
    throw FormatException(errorMessage);
  }
}

// ---------- Storage contract ----------

/// Defines persistence operations for editor-owned attachment bytes.
/// Implemented by the browser attachment store.
abstract interface class AttachmentStore {
  Future<void> write(String path, Uint8List bytes);

  Future<void> delete(String path);

  Future<Uint8List> read(String path);

  Future<Uint8List?> readIfExists(String path);
}

// ---------- Path validation ----------

final attachmentPathPattern = RegExp(
  r'^attachments/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(?:png|jpg|gif|webp)$',
);

String attachmentFileName(String path) {
  if (!attachmentPathPattern.hasMatch(path)) {
    throw const FormatException('Invalid attachment path');
  }
  return path.substring('attachments/'.length);
}
