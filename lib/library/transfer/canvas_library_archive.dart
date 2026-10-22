// Encodes and validates whole-library ZIP backups with visible folder and canvas files.
// Used by the canvas editor's library backup and restore actions.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:uuid/uuid.dart';

// ---------- Models ----------

/// Holds a validated library and its image bytes before restore commits them.
/// Used by the editor after ZIP decoding and before replacement confirmation.
typedef CanvasLibraryArchive = ({CanvasLibrary library, Map<String, Uint8List> attachments});

// ---------- Encoding ----------

Future<Uint8List> encodeCanvasLibraryArchive(CanvasLibrary library, AttachmentStore store) async {
  for (final file in library.files) {
    if (library.nameError(file.name, file.parentId, exceptId: file.id) != null) {
      throw const FormatException('Invalid or duplicate library name');
    }
  }
  final archive = Archive()..add(ArchiveFile.directory('library/'));
  final occupied = <String>{};
  final paths = <String, String>{};
  var totalBytes = 0;

  for (final folder in library.files.where((file) => file.isFolder)) {
    final path = 'library/${library.path(folder.id).map((part) => _segment(part.name)).join('/')}/';
    paths[folder.id] = path;
    if (!occupied.add(path.substring(0, path.length - 1).toLowerCase())) {
      throw const FormatException('Duplicate folder path');
    }
    archive.add(ArchiveFile.directory(path));
  }

  final imagePaths = <String>{};
  for (final canvas in library.files.where((file) => !file.isFolder)) {
    final parent = canvas.parentId == null ? 'library/' : paths[canvas.parentId];
    if (parent == null) throw const FormatException('Missing folder');
    final name = _segment(canvas.name);
    var path = '$parent$name.json';
    for (var suffix = 2; !occupied.add(path.toLowerCase()); suffix++) {
      path = '$parent$name (canvas $suffix).json';
    }
    final document = canvas.document!;
    imagePaths.addAll(canvasAttachmentPaths(document));
    final data = utf8.encode(jsonEncode({'version': 1, 'name': canvas.name, 'document': document.toJson()}));
    totalBytes += data.length;
    validateCanvasProjectSize(totalBytes);
    archive.add(ArchiveFile.bytes(path, data));
  }

  if (imagePaths.isNotEmpty) archive.add(ArchiveFile.directory('attachments/'));
  for (final path in imagePaths.toList()..sort()) {
    final bytes = await store.readIfExists(path);
    if (bytes == null) throw FormatException('A canvas image is missing: $path');
    await validateCanvasAttachment(path, bytes);
    totalBytes += bytes.length;
    validateCanvasProjectSize(totalBytes);
    archive.add(ArchiveFile.bytes(path, bytes));
  }

  final bytes = ZipEncoder().encodeBytes(archive);
  validateCanvasProjectSize(bytes.length);
  return bytes;
}

// ---------- Decoding ----------

Future<CanvasLibraryArchive> decodeCanvasLibraryArchive(Uint8List bytes) async {
  validateCanvasProjectSize(bytes.length);
  final decoder = ZipDecoder();
  final archive = decoder.decodeBytes(bytes);
  final names = <String>{};
  var totalBytes = 0;
  for (final header in decoder.directory.fileHeaders) {
    if (!names.add(header.filename) || header.uncompressedSize < 0) {
      throw const FormatException('Duplicate or invalid ZIP entry');
    }
    totalBytes += header.uncompressedSize;
    validateCanvasProjectSize(totalBytes);
  }
  if (names.length != archive.length || !names.contains('library/')) {
    throw const FormatException('Invalid library ZIP');
  }
  for (final root in archive.where((entry) => entry.name == 'library/' || entry.name == 'attachments/')) {
    if (!root.isDirectory || root.isSymbolicLink) throw const FormatException('Invalid ZIP root');
  }

  final folders = <String, String?>{'library/': null};
  final folderEntries =
      archive
          .where((entry) => entry.isDirectory && entry.name.startsWith('library/') && entry.name != 'library/')
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  final files = <CanvasFile>[];

  for (final entry in folderEntries) {
    if (entry.isSymbolicLink || !entry.name.endsWith('/')) throw const FormatException('Invalid folder entry');
    final parent = _parentPath(entry.name.substring(0, entry.name.length - 1));
    if (!folders.containsKey(parent)) throw const FormatException('Missing parent folder');
    final name = _decodedSegment(entry.name.substring(parent.length, entry.name.length - 1));
    final id = const Uuid().v4();
    files.add(CanvasFile(id: id, name: name, parentId: folders[parent]));
    folders[entry.name] = id;
  }

  final canvasEntries = archive.where((entry) => entry.isFile && entry.name.startsWith('library/')).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  for (final entry in canvasEntries) {
    final parent = _parentPath(entry.name);
    if (entry.isSymbolicLink || !folders.containsKey(parent) || !entry.name.endsWith('.json')) {
      throw const FormatException('Invalid canvas entry');
    }
    _decodedSegment(entry.name.substring(parent.length, entry.name.length - 5));
    final content = _checkedBytes(entry);
    final root = jsonDecode(utf8.decode(content, allowMalformed: false));
    if (root is! Map<String, dynamic> || root.length != 3 || root['version'] != 1 || root['name'] is! String) {
      throw const FormatException('Invalid canvas file');
    }
    files.add(
      CanvasFile(
        id: const Uuid().v4(),
        name: root['name'] as String,
        parentId: folders[parent],
        document: CanvasDocument.fromJson(root['document']),
      ),
    );
  }

  if (files.every((file) => file.isFolder)) throw const FormatException('Library has no canvases');
  final library = CanvasLibrary(
    files: files,
    currentId: files.firstWhere((file) => !file.isFolder).id,
  );
  for (final file in library.files) {
    if (library.nameError(file.name, file.parentId, exceptId: file.id) != null) {
      throw const FormatException('Invalid or duplicate library name');
    }
  }

  final attachments = <String, Uint8List>{};
  for (final entry in archive) {
    if (entry.name.startsWith('library/') || entry.name == 'attachments/') {
      continue;
    }
    if (!entry.isFile || entry.isSymbolicLink || !attachmentPathPattern.hasMatch(entry.name)) {
      throw const FormatException('Unexpected ZIP entry');
    }
    final data = _checkedBytes(entry);
    await validateCanvasAttachment(entry.name, data);
    attachments[entry.name] = data;
  }
  final referenced = library.files
      .where((file) => !file.isFolder)
      .expand((file) => canvasAttachmentPaths(file.document!))
      .toSet();
  if (referenced.length != attachments.length || !referenced.containsAll(attachments.keys)) {
    throw const FormatException('Attachment references do not match the ZIP');
  }
  return (library: library, attachments: attachments);
}

// ---------- Helpers ----------

Uint8List _checkedBytes(ArchiveFile entry) {
  final data = entry.readBytes();
  if (data == null || data.length != entry.size || getCrc32(data) != entry.crc32) {
    throw FormatException('Damaged ZIP entry: ${entry.name}');
  }
  return data;
}

String _parentPath(String path) => path.substring(0, path.lastIndexOf('/') + 1);

String _segment(String name) {
  var encoded = Uri.encodeComponent(name).replaceAll('%20', ' ');
  if (encoded == '.' || encoded == '..') encoded = encoded.replaceAll('.', '%2E');
  if (encoded.endsWith('.')) encoded = '${encoded.substring(0, encoded.length - 1)}%2E';
  if (encoded.endsWith(' ')) encoded = '${encoded.substring(0, encoded.length - 1)}%20';
  if (RegExp(r'^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)', caseSensitive: false).hasMatch(encoded)) {
    encoded = '%${encoded.codeUnitAt(0).toRadixString(16).padLeft(2, '0').toUpperCase()}${encoded.substring(1)}';
  }
  return encoded;
}

String _decodedSegment(String encoded) {
  final name = Uri.decodeComponent(encoded);
  if (name.isEmpty || _segment(name) != encoded) throw const FormatException('Invalid ZIP path');
  return name;
}
