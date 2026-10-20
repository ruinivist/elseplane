// Validates, encodes, and decodes portable canvas project archives.
// Used by the editor's import and export flows.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:uuid/uuid.dart';

// ---------- Limits ----------

const int canvasProjectMaximumBytes = 140 * 1024 * 1024;
const int _maximumEncodedAttachmentLength = ((attachmentMaximumBytes + 2) ~/ 3) * 4;

// ---------- Validation ----------

void validateCanvasProjectSize(int length) {
  if (length > canvasProjectMaximumBytes) {
    throw const FormatException('Project exceeds 140 MiB');
  }
}

// ---------- Models ----------

/// Holds a decoded canvas document and all referenced attachment bytes.
/// Returned by project import for replacement of editor persistence.
final class CanvasProject {
  const CanvasProject({required this.document, required this.attachments});

  final CanvasDocument document;
  final Map<String, Uint8List> attachments;
}

// ---------- Attachment discovery ----------

Set<String> canvasAttachmentPaths(CanvasDocument document) {
  final paths = <String>{};
  for (final element in document.elements) {
    if (element case TextElementData(:final markdown)) {
      for (final node in md.Document().parse(markdown)) {
        _collectAttachmentPaths(node, paths);
      }
    } else if (element case MediaElementData(:final url)) {
      final path = url.trim();
      if (attachmentPathPattern.hasMatch(path)) paths.add(path);
    }
  }
  return paths;
}

// ---------- Encoding and decoding ----------

/// Gives imported images fresh paths when another canvas already uses them.
/// Prevents project imports from replacing another saved canvas's image bytes.
CanvasProject rebaseCanvasProjectAttachments(CanvasProject project, Set<String> reservedPaths) {
  final replacements = <String, String>{
    for (final path in project.attachments.keys)
      if (reservedPaths.contains(path)) path: 'attachments/${const Uuid().v4()}.${path.split('.').last}',
  };
  if (replacements.isEmpty) return project;
  return CanvasProject(
    document: rebaseCanvasDocumentAttachments(project.document, replacements),
    attachments: {
      for (final entry in project.attachments.entries) replacements[entry.key] ?? entry.key: entry.value,
    },
  );
}

CanvasDocument rebaseCanvasDocumentAttachments(CanvasDocument source, Map<String, String> replacements) {
  return source.copyWith(
    elements: [
      for (final element in source.elements)
        switch (element) {
          MediaElementData() => element.copyWith(url: replacements[element.url.trim()] ?? element.url),
          TextElementData() => element.copyWith(
            markdown: replacements.entries.fold<String>(
              element.markdown,
              (markdown, entry) => markdown.replaceAll(entry.key, entry.value),
            ),
          ),
          _ => element,
        },
    ],
  );
}

/// Encodes a document and its referenced attachments as a portable project.
/// Used by the canvas export flow before saving to the host file system.
Future<Uint8List> encodeCanvasProject(
  CanvasDocument document,
  AttachmentStore store,
) async {
  final paths = canvasAttachmentPaths(document).toList()..sort();
  final attachments = <String, String>{};

  for (final path in paths) {
    final bytes = await store.read(path);
    validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
    attachments[path] = base64Encode(bytes);
  }

  final bytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object>{
        'format': 'elseplane-canvas',
        'document': document.toJson(),
        'attachments': attachments,
      }),
    ),
  );
  validateCanvasProjectSize(bytes.length);
  return bytes;
}

/// Validates and decodes a portable project and all embedded attachments.
/// Used by the canvas import flow before replacing editor state.
Future<CanvasProject> decodeCanvasProject(Uint8List bytes) async {
  validateCanvasProjectSize(bytes.length);

  final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));

  final root = _jsonObject(
    decoded,
    'project',
    allowedKeys: const {'format', 'document', 'attachments'},
  );
  if (root['format'] != 'elseplane-canvas') {
    throw const FormatException('project.format must be elseplane-canvas');
  }

  final document = CanvasDocument.fromJson(root['document']);
  final encodedAttachments = _jsonMap(
    root['attachments'],
    'project.attachments',
  );
  final attachments = <String, Uint8List>{};

  for (final entry in encodedAttachments.entries) {
    if (!attachmentPathPattern.hasMatch(entry.key)) {
      throw FormatException('Invalid attachment path: ${entry.key}');
    }
    final encoded = entry.value;
    if (encoded is! String) {
      throw FormatException('Attachment value must be base64: ${entry.key}');
    }
    if (encoded.length > _maximumEncodedAttachmentLength) {
      throw FormatException('Attachment exceeds 10 MiB: ${entry.key}');
    }

    late final Uint8List attachment;
    try {
      attachment = base64Decode(encoded);
    } on FormatException {
      throw FormatException('Invalid base64 attachment: ${entry.key}');
    }
    validateAttachmentSize(
      attachment.length,
      'Attachment exceeds 10 MiB: ${entry.key}',
    );
    if (base64Encode(attachment) != encoded) {
      throw FormatException('Invalid base64 attachment: ${entry.key}');
    }
    attachments[entry.key] = attachment;
  }

  final referencedPaths = canvasAttachmentPaths(document);
  if (attachments.length != referencedPaths.length || !referencedPaths.containsAll(attachments.keys)) {
    throw const FormatException('Attachment references do not match the map');
  }

  for (final path in referencedPaths) {
    await validateCanvasAttachment(path, attachments[path]!);
  }

  return CanvasProject(document: document, attachments: attachments);
}

// ---------- Private helpers ----------

void _collectAttachmentPaths(md.Node node, Set<String> paths) {
  if (node is! md.Element) return;
  if (node.tag == 'img') {
    final source = node.attributes['src'];
    if (source != null && attachmentPathPattern.hasMatch(source)) {
      paths.add(source);
    }
  }
  for (final child in node.children ?? const <md.Node>[]) {
    _collectAttachmentPaths(child, paths);
  }
}

Map<String, Object?> _jsonObject(
  Object? value,
  String field, {
  required Set<String> allowedKeys,
}) {
  final result = _jsonMap(value, field);
  for (final key in result.keys) {
    if (!allowedKeys.contains(key)) {
      throw FormatException('$field has unknown key: $key');
    }
  }
  return result;
}

Map<String, Object?> _jsonMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$field must have string keys');
    }
    final key = entry.key as String;
    result[key] = entry.value;
  }
  return result;
}

Future<void> validateCanvasAttachment(String path, Uint8List bytes) async {
  if (!attachmentPathPattern.hasMatch(path)) throw FormatException('Invalid attachment path: $path');
  validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
  ImmutableBuffer? buffer;
  ImageDescriptor? descriptor;
  try {
    buffer = await ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ImageDescriptor.encoded(buffer);
  } catch (error) {
    throw FormatException('Invalid encoded image: $path ($error)');
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
