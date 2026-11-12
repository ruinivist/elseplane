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

/// Copies available bytes between complete keys without replacing different data.
/// Used by hierarchy and clipboard operations that retain their source paths.
Future<List<String>> copyAttachmentPaths(
  AttachmentStore store,
  Map<String, String> sourceToDestination, {
  void Function(String path)? beforeWrite,
}) async {
  final pairs = sourceToDestination.entries.toList()
    ..sort((a, b) {
      final source = a.key.compareTo(b.key);
      return source != 0 ? source : a.value.compareTo(b.value);
    });
  for (final pair in pairs) {
    validateAttachmentPath(pair.key);
    validateAttachmentPath(pair.value);
  }

  final sourceBytes = <String, Uint8List>{};
  for (final pair in pairs) {
    if (sourceBytes.containsKey(pair.key)) continue;
    final bytes = await store.readIfExists(pair.key);
    if (bytes != null) {
      validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: ${pair.key}');
      sourceBytes[pair.key] = bytes;
    }
  }

  final expectedByDestination = <String, Uint8List>{};
  for (final pair in pairs) {
    final bytes = sourceBytes[pair.key];
    if (bytes == null) continue;
    final expected = expectedByDestination.putIfAbsent(pair.value, () => bytes);
    if (!_sameBytes(expected, bytes)) {
      throw FormatException('Attachment destination conflict: ${pair.value}');
    }
  }

  final destinationBytes = <String, Uint8List?>{};
  for (final path in expectedByDestination.keys.toList()..sort()) {
    final bytes = await store.readIfExists(path);
    if (bytes != null) validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
    destinationBytes[path] = bytes;
  }
  for (final entry in expectedByDestination.entries) {
    final existing = destinationBytes[entry.key];
    if (existing != null && !_sameBytes(existing, entry.value)) {
      throw FormatException('Attachment destination conflict: ${entry.key}');
    }
  }

  final written = <String>[];
  for (final path in expectedByDestination.keys.toList()..sort()) {
    if (destinationBytes[path] != null) continue;
    beforeWrite?.call(path);
    await store.write(path, expectedByDestination[path]!);
    written.add(path);
  }
  return List.unmodifiable(written);
}

bool _sameBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
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

/// Validates a literal root-relative directory, with the root represented by ''.
void validateAttachmentDirectory(String canvasDirectory) {
  _validateDirectoryPath(canvasDirectory, allowEmpty: true);
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
