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

/// Defines byte storage shared by editor resources and library transfers.
/// Implemented by platform attachment stores.
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
  validateAttachmentPath(path);
  return path.split('/').last;
}

bool isCanvasAttachmentReference(String value) => attachmentPathPattern.hasMatch(value);

void validateAttachmentPath(String rootRelativePath) {
  final segments = _validateDirectoryPath(rootRelativePath, allowEmpty: false);
  if (segments.length < 2 ||
      segments[segments.length - 2] != 'attachments' ||
      !_attachmentFilePattern.hasMatch(segments.last)) {
    throw const FormatException('Invalid attachment path');
  }
}

String resolveAttachmentPath(String canvasDirectory, String reference) {
  if (!isCanvasAttachmentReference(reference)) {
    throw const FormatException('Invalid canvas attachment reference');
  }
  final directory = _validateDirectoryPath(canvasDirectory, allowEmpty: true);
  final path = [...directory, reference].join('/');
  validateAttachmentPath(path);
  return path;
}

final _attachmentFilePattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(?:png|jpg|gif|webp)$',
);
final _uriSchemePattern = RegExp('^[A-Za-z][A-Za-z0-9+.-]*:');
final _drivePrefixPattern = RegExp('^[A-Za-z]:');
final _controlCharactersPattern = RegExp(r'[\u0000-\u001F\u007F-\u009F]');

List<String> _validateDirectoryPath(String path, {required bool allowEmpty}) {
  if (path.isEmpty) {
    if (allowEmpty) return const [];
    throw const FormatException('Invalid attachment path');
  }
  if (path.startsWith('/') ||
      path.endsWith('/') ||
      path.contains(r'\') ||
      _controlCharactersPattern.hasMatch(path) ||
      _uriSchemePattern.hasMatch(path)) {
    throw const FormatException('Invalid attachment path');
  }

  final segments = path.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..' || _drivePrefixPattern.hasMatch(segment),
  )) {
    throw const FormatException('Invalid attachment path');
  }
  return segments;
}
