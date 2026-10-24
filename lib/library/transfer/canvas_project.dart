// Validates, encodes, and decodes portable canvas project archives.
// Used by the editor's import and export flows.

import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:flutter_markdown_plus/latex.dart';
import 'package:markdown/markdown.dart' as md;

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
      for (final image in _markdownImages(markdown)) {
        final path = image.attributes['src']!;
        if (attachmentPathPattern.hasMatch(path)) paths.add(path);
      }
    } else if (element case MediaElementData(:final url)) {
      final path = url.trim();
      if (attachmentPathPattern.hasMatch(path)) paths.add(path);
    }
  }
  return paths;
}

// ---------- Encoding and decoding ----------

CanvasDocument rebaseCanvasDocumentAttachments(CanvasDocument source, Map<String, String> replacements) {
  return source.copyWith(
    elements: [
      for (final element in source.elements)
        switch (element) {
          MediaElementData() => element.copyWith(url: replacements[element.url.trim()] ?? element.url),
          TextElementData() => element.copyWith(
            markdown: _rebaseMarkdownAttachments(element.markdown, replacements),
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

Iterable<md.Element> _markdownImages(String source) => _imageNodes(
  md.Document(
    extensionSet: md.ExtensionSet(
      [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, const LatexBlockSyntax()],
      [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexInlineSyntax()],
    ),
    encodeHtml: false,
  ).parse(source),
);

Iterable<md.Element> _imageNodes(List<md.Node> nodes) sync* {
  for (final node in nodes.whereType<md.Element>()) {
    if (node.tag == 'img') yield node;
    if (node.children != null) yield* _imageNodes(node.children!);
  }
}

String _rebaseMarkdownAttachments(String source, Map<String, String> replacements) {
  if (replacements.isEmpty) return source;
  final edits = <md.SourceRange, String>{};
  for (final image in _markdownImages(source)) {
    final path = image.attributes['src']!;
    final replacement = replacements[path];
    final range = image.destinationRange;
    if (attachmentPathPattern.hasMatch(path) && replacement != null && range != null) {
      edits[range] = replacement;
    }
  }
  final ranges = edits.keys.toList()..sort((a, b) => b.start.compareTo(a.start));
  var rebased = source;
  for (final range in ranges) {
    rebased = rebased.replaceRange(range.start, range.end, edits[range]!);
  }
  return rebased;
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
