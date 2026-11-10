// Prepares and validates single-canvas data for GitHub transfers.

import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';

Future<CanvasProject> prepareCanvasRemoteTransfer(CanvasDocument document, AttachmentStore store) async {
  final documentBytes = encodeRemoteCanvasDocument(document);
  var totalBytes = documentBytes.length;
  validateCanvasProjectSize(totalBytes);
  final attachments = <String, Uint8List>{};
  for (final path in canvasAttachmentPaths(document).toList()..sort()) {
    final bytes = await store.read(path);
    await validateCanvasAttachment(path, bytes);
    if (bytes.length > canvasProjectMaximumBytes - totalBytes) {
      throw const FormatException('Project exceeds 140 MiB');
    }
    totalBytes += bytes.length;
    attachments[path] = bytes;
  }
  return CanvasProject(document: document, attachments: attachments);
}

Future<CanvasProject> decodeCanvasRemoteTransfer(
  Uint8List documentBytes,
  Map<String, Uint8List> attachments,
) async {
  validateCanvasProjectSize(documentBytes.length);
  late final CanvasDocument document;
  try {
    document = CanvasDocument.fromJson(jsonDecode(utf8.decode(documentBytes, allowMalformed: false)));
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Invalid canvas document: $error');
  }

  final referenced = canvasAttachmentPaths(document);
  if (referenced.length != attachments.length || !referenced.containsAll(attachments.keys)) {
    throw const FormatException('Attachment references do not match the canvas');
  }
  var totalBytes = documentBytes.length;
  for (final entry in attachments.entries) {
    await validateCanvasAttachment(entry.key, entry.value);
    if (entry.value.length > canvasProjectMaximumBytes - totalBytes) {
      throw const FormatException('Project exceeds 140 MiB');
    }
    totalBytes += entry.value.length;
  }
  return CanvasProject(document: document, attachments: Map.unmodifiable(attachments));
}

Uint8List encodeRemoteCanvasDocument(CanvasDocument document) => Uint8List.fromList(
  utf8.encode(const JsonEncoder.withIndent('  ').convert(document.toJson())),
);

String canvasRemotePath(CanvasLibrary library, String fileId) {
  final canvas = library.file(fileId);
  if (canvas.isFolder) throw ArgumentError('A folder has no canvas path');
  final lineage = library.path(fileId);
  for (final entry in lineage) {
    _validateRemoteSegment(entry.name);
  }
  final folders = lineage.take(lineage.length - 1).toList();
  if (folders.any((folder) => folder.name == 'attachments') ||
      library.files.any(
        (file) => file.isFolder && file.parentId == canvas.parentId && file.name == 'attachments',
      )) {
    throw const FormatException('A local attachments folder conflicts with GitHub images');
  }

  final path = [...folders.map((folder) => folder.name), '${canvas.name}.canvas'].join('/');
  final parentDirectories = <String>[
    for (var index = 1; index <= folders.length; index++) folders.take(index).map((folder) => folder.name).join('/'),
  ];
  for (final entry in library.files) {
    if (entry.id == fileId) continue;
    final candidatePath = library.path(entry.id);
    final candidate = [
      ...candidatePath.take(entry.isFolder ? candidatePath.length : candidatePath.length - 1).map((part) => part.name),
      if (!entry.isFolder) '${entry.name}.canvas',
    ].join('/');
    if (entry.isFolder && (candidate == path || candidate.startsWith('$path/'))) {
      throw const FormatException('GitHub canvas path collides with a folder');
    }
    if (!entry.isFolder &&
        (candidate == path ||
            parentDirectories.any((directory) => candidate == directory || directory.startsWith('$candidate/')))) {
      throw const FormatException('GitHub canvas path collides with another canvas');
    }
  }
  return path;
}

void _validateRemoteSegment(String segment) {
  if (segment.isEmpty ||
      segment == '.' ||
      segment == '..' ||
      segment.contains('/') ||
      segment.contains(r'\') ||
      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(segment)) {
    throw FormatException('Invalid GitHub path segment: $segment');
  }
}
