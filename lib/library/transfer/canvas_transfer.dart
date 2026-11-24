// Defines shared transfer values, codecs, and literal path validation.

import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/attachment_references.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';

const int canvasTransferMaximumBytes = 140 * 1024 * 1024;
const _canvasDocumentSuffix = '.canvas.json';

void validateCanvasTransferSize(int byteLength) {
  if (byteLength > canvasTransferMaximumBytes) {
    throw const FormatException('Transfer exceeds 140 MiB');
  }
}

enum TransferScope { currentCanvas, wholeLibrary }

final class TransferTree {
  TransferTree({required Map<String, Uint8List> files, Set<String> directories = const {}})
    : files = Map.unmodifiable({for (final entry in files.entries) entry.key: _immutableBytes(entry.value)}),
      directories = Set.unmodifiable(directories) {
    validateTransferEntries([
      for (final path in this.files.keys) TransferEntry(path: path, kind: TransferEntryKind.regularFile),
      for (final path in this.directories) TransferEntry(path: path, kind: TransferEntryKind.directory),
    ]);
  }

  final Map<String, Uint8List> files;
  final Set<String> directories;
}

enum TransferEntryKind { regularFile, directory, unsupported }

final class TransferEntry {
  TransferEntry({required this.path, required this.kind, this.size}) {
    validateTransferPath(path);
  }

  final String path;
  final TransferEntryKind kind;
  final int? size;
}

abstract interface class TransferSource {
  Future<List<TransferEntry>> entries();

  Future<Uint8List> read(String path);
}

/// A selected standalone document, represented as one root canvas file.
final class StandaloneCanvasTransferSource implements TransferSource {
  StandaloneCanvasTransferSource({required String name, required Uint8List bytes})
    : _path = _canvasPathFromName(name),
      _bytes = _boundedTransferCopy(bytes);

  final String _path;
  final Uint8List _bytes;

  @override
  Future<List<TransferEntry>> entries() async => [
    TransferEntry(path: _path, kind: TransferEntryKind.regularFile, size: _bytes.length),
  ];

  @override
  Future<Uint8List> read(String path) async {
    if (path != _path) throw FormatException('Unknown transfer path: $path');
    return Uint8List.fromList(_bytes);
  }
}

final class TransferImport {
  TransferImport({
    required Map<String, CanvasDocument> canvases,
    required Map<String, Uint8List> attachments,
    required Set<String> directories,
    required List<TransferIssue> skippedCanvases,
  }) : canvases = Map.unmodifiable(canvases),
       attachments = Map.unmodifiable({
         for (final entry in attachments.entries) entry.key: _immutableBytes(entry.value),
       }),
       directories = Set.unmodifiable(directories),
       skippedCanvases = List.unmodifiable(skippedCanvases) {
    validateTransferEntries([
      for (final path in this.canvases.keys) TransferEntry(path: path, kind: TransferEntryKind.regularFile),
      for (final path in this.attachments.keys) TransferEntry(path: path, kind: TransferEntryKind.regularFile),
      for (final path in this.directories) TransferEntry(path: path, kind: TransferEntryKind.directory),
    ]);
  }

  final Map<String, CanvasDocument> canvases;
  final Map<String, Uint8List> attachments;
  final Set<String> directories;
  final List<TransferIssue> skippedCanvases;
}

final class TransferIssue {
  const TransferIssue({required this.path, required this.reason});

  final String path;
  final String reason;
}

final class TransferMerge {
  TransferMerge({required this.candidate, required this.expectedChangeRevision, required Set<String> overwritePaths})
    : overwritePaths = Set.unmodifiable(overwritePaths);

  final TransferImport candidate;
  final int expectedChangeRevision;
  final Set<String> overwritePaths;
}

final class TransferImportResult {
  TransferImportResult({
    required List<TransferIssue> skippedCanvases,
    required List<String> writtenImagePaths,
    required this.metadataSaved,
    this.failure,
  }) : skippedCanvases = List.unmodifiable(skippedCanvases),
       writtenImagePaths = List.unmodifiable(writtenImagePaths);

  final List<TransferIssue> skippedCanvases;
  final List<String> writtenImagePaths;
  final bool metadataSaved;
  final TransferFailure? failure;
}

enum TransferFailureStage { preparation, imageWrite, publication }

final class TransferFailure {
  const TransferFailure({required this.reason, required this.stage, this.path});

  final String? path;
  final String reason;
  final TransferFailureStage stage;
}

/// Encodes the captured library snapshot as direct document JSON and images.
Future<TransferTree> encodeTransfer(
  CanvasLibrary captured,
  AttachmentStore attachments,
  TransferScope scope,
) async {
  final files = <String, Uint8List>{};
  final directories = <String>{};
  final canvases = switch (scope) {
    TransferScope.currentCanvas => [captured.current],
    TransferScope.wholeLibrary => captured.files.where((file) => !file.isFolder).toList(),
  };

  if (scope == TransferScope.wholeLibrary) {
    captured.validatePaths();
    directories.addAll(
      captured.files
          .where((file) => file.isFolder)
          .map((file) => captured.path(file.id).map((part) => part.name).join('/')),
    );
  } else {
    for (final folder in captured.path(captured.currentId).where((file) => file.isFolder)) {
      if (folder.name == 'attachments' || folder.name == '.git') {
        throw FormatException('Reserved folder name: ${folder.name}');
      }
      directories.add(captured.path(folder.id).map((part) => part.name).join('/'));
    }
  }

  final imagePaths = <String>{};
  var totalBytes = 0;
  for (final canvas in canvases) {
    final document = canvas.document!;
    final documentPath = captured.serializedPath(canvas.id);
    validateTransferPath(documentPath);
    final documentBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(document.toJson())),
    );
    totalBytes += documentBytes.length;
    validateCanvasTransferSize(totalBytes);
    files[documentPath] = documentBytes;

    final parent = captured.parentDirectory(canvas.id);
    for (final reference in canvasAttachmentPaths(document.elements)) {
      imagePaths.add(resolveAttachmentPath(parent, reference));
    }
  }

  for (final path in imagePaths.toList()..sort()) {
    final bytes = await attachments.readIfExists(path);
    if (bytes == null) continue;
    validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
    totalBytes += bytes.length;
    validateCanvasTransferSize(totalBytes);
    files[path] = bytes;
  }

  return TransferTree(files: files, directories: directories);
}

/// Validates a complete source and decodes its supported canvas documents.
Future<TransferImport> decodeTransfer(
  TransferSource source, {
  int maxConcurrentReads = 1,
  bool Function()? isCurrent,
}) async {
  if (maxConcurrentReads < 1) throw ArgumentError.value(maxConcurrentReads, 'maxConcurrentReads');
  final sourceEntries = await source.entries();
  _checkTransferDecodeCurrent(isCurrent);
  for (final entry in sourceEntries) {
    if (entry.kind == TransferEntryKind.unsupported) {
      throw FormatException('Unsupported transfer entry: ${entry.path}');
    }
    if (entry.size != null && entry.size! < 0) {
      throw FormatException('Invalid transfer entry size: ${entry.path}');
    }
  }
  final directories = validateTransferEntries(sourceEntries);
  final entriesByPath = {for (final entry in sourceEntries) entry.path: entry};
  var declaredTotal = 0;
  final imagePaths = <String>{};
  final documentPaths = <String>[];
  for (final entry in sourceEntries) {
    if (entry.kind == TransferEntryKind.directory) {
      if (entry.size != null && entry.size != 0) {
        throw FormatException('Invalid transfer directory size: ${entry.path}');
      }
      continue;
    }
    final size = entry.size;
    final isDocument = _isCanvasPath(entry.path);
    final isImage = _isAttachmentPath(entry.path);
    if (size == null && (_insideGitMetadata(entry.path) || (!isDocument && !isImage))) {
      throw FormatException('Missing transfer entry size: ${entry.path}');
    }
    if (size != null) {
      declaredTotal += size;
      validateCanvasTransferSize(declaredTotal);
    }
    if (isImage) {
      validateAttachmentPath(entry.path);
      final segments = entry.path.split('/');
      if (segments.take(segments.length - 2).any((segment) => segment == 'attachments')) {
        throw FormatException('Invalid attachment path: ${entry.path}');
      }
      if (size != null) validateAttachmentSize(size, 'Attachment exceeds 10 MiB: ${entry.path}');
    }
    if (_insideGitMetadata(entry.path)) continue;
    if (isDocument) {
      if (_insideAttachmentNamespace(entry.path)) {
        throw FormatException('Canvas inside attachments namespace: ${entry.path}');
      }
      final fileName = entry.path.split('/').last;
      final name = fileName.substring(0, fileName.length - _canvasDocumentSuffix.length);
      if (name.isEmpty || name.trim().isEmpty) throw FormatException('Invalid canvas path: ${entry.path}');
      documentPaths.add(entry.path);
    } else if (isImage) {
      imagePaths.add(entry.path);
    }
  }

  final pathsToRead = [...documentPaths, ...imagePaths]..sort();
  final payloads = <String, Uint8List>{};
  var actualTotal = 0;
  var nextPathIndex = 0;
  var stopped = false;

  Future<void> readWorker() async {
    try {
      while (true) {
        if (stopped) return;
        if (!_isTransferDecodeCurrent(isCurrent)) throw const _TransferDecodeCancelled();
        if (nextPathIndex == pathsToRead.length) return;

        final path = pathsToRead[nextPathIndex++];
        final bytes = await source.read(path);
        if (!_isTransferDecodeCurrent(isCurrent)) throw const _TransferDecodeCancelled();
        if (stopped) return;

        final declaredSize = entriesByPath[path]!.size;
        if (declaredSize != null && bytes.length != declaredSize) {
          throw FormatException('Transfer entry size mismatch: $path');
        }
        if (imagePaths.contains(path)) validateAttachmentSize(bytes.length, 'Attachment exceeds 10 MiB: $path');
        actualTotal += bytes.length;
        validateCanvasTransferSize(actualTotal);
        payloads[path] = bytes;
      }
    } on Object {
      stopped = true;
      rethrow;
    }
  }

  final workerCount = pathsToRead.length < maxConcurrentReads ? pathsToRead.length : maxConcurrentReads;
  await Future.wait<void>(
    [for (var index = 0; index < workerCount; index++) readWorker()],
    eagerError: true,
  );
  _checkTransferDecodeCurrent(isCurrent);

  final canvases = <String, CanvasDocument>{};
  final skipped = <TransferIssue>[];
  for (final path in documentPaths) {
    final decoded = _decodeCanvas(path, payloads[path]!);
    if (decoded.document != null) {
      canvases[path] = decoded.document!;
    } else {
      skipped.add(decoded.issue!);
    }
  }

  final referencedImages = <String>{};
  for (final entry in canvases.entries) {
    final pathParts = entry.key.split('/');
    final parent = pathParts.length == 1 ? '' : pathParts.take(pathParts.length - 1).join('/');
    for (final reference in canvasAttachmentPaths(entry.value.elements)) {
      referencedImages.add(resolveAttachmentPath(parent, reference));
    }
  }
  final attachments = <String, Uint8List>{};
  for (final path in referencedImages) {
    final bytes = payloads[path];
    if (bytes != null) attachments[path] = bytes;
  }
  final explorerDirectories = directories.where(
    (path) => !_insideGitMetadata(path) && !_insideAttachmentNamespace(path),
  );
  return TransferImport(
    canvases: canvases,
    attachments: attachments,
    directories: explorerDirectories.toSet(),
    skippedCanvases: skipped,
  );
}

bool _isTransferDecodeCurrent(bool Function()? isCurrent) => isCurrent == null || isCurrent();

void _checkTransferDecodeCurrent(bool Function()? isCurrent) {
  if (!_isTransferDecodeCurrent(isCurrent)) throw const _TransferDecodeCancelled();
}

final class _TransferDecodeCancelled implements Exception {
  const _TransferDecodeCancelled();
}

({CanvasDocument? document, TransferIssue? issue}) _decodeCanvas(String path, Uint8List bytes) {
  late final String source;
  try {
    source = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return (document: null, issue: TransferIssue(path: path, reason: 'Invalid UTF-8'));
  }

  late final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException {
    return (document: null, issue: TransferIssue(path: path, reason: 'Invalid JSON'));
  }
  if (json is Map && json['version'] is int && json['version'] != CanvasDocument.version) {
    return (document: null, issue: TransferIssue(path: path, reason: 'Unsupported canvas schema'));
  }
  try {
    return (document: CanvasDocument.fromJson(json), issue: null);
  } on FormatException {
    return (document: null, issue: TransferIssue(path: path, reason: 'Invalid canvas schema'));
  }
}

String _canvasPathFromName(String name) {
  if (!name.endsWith(_canvasDocumentSuffix)) throw const FormatException('Unsupported transfer file');
  final canvasName = name.substring(0, name.length - _canvasDocumentSuffix.length);
  if (canvasName.isEmpty || canvasName.trim().isEmpty || canvasName.contains('/') || canvasName.contains(r'\')) {
    throw const FormatException('Invalid canvas filename');
  }
  final path = '$canvasName$_canvasDocumentSuffix';
  validateTransferPath(path);
  return path;
}

bool _isCanvasPath(String path) => path.endsWith(_canvasDocumentSuffix);

bool _isAttachmentPath(String path) {
  final segments = path.split('/');
  return segments.length >= 2 && segments[segments.length - 2] == 'attachments';
}

bool _insideGitMetadata(String path) => path.split('/').contains('.git');

bool _insideAttachmentNamespace(String path) => path.split('/').contains('attachments');

/// Validates one literal root-relative transfer path without normalizing it.
void validateTransferPath(String path) {
  if (path.isEmpty) throw const FormatException('Invalid transfer path');
  validateAttachmentDirectory(path);
}

/// Validates exact entries and returns all explicit and implied directories.
Set<String> validateTransferEntries(Iterable<TransferEntry> entries) {
  final seen = <String>{};
  final files = <String>{};
  final directories = <String>{};

  for (final entry in entries) {
    validateTransferPath(entry.path);
    if (!seen.add(entry.path)) throw FormatException('Duplicate transfer path: ${entry.path}');
    if (entry.kind == TransferEntryKind.directory) {
      directories.add(entry.path);
    } else {
      files.add(entry.path);
    }
    final segments = entry.path.split('/');
    for (var length = 1; length < segments.length; length++) {
      directories.add(segments.take(length).join('/'));
    }
  }

  final conflicts = files.intersection(directories).toList()..sort();
  if (conflicts.isNotEmpty) throw FormatException('Conflicting transfer path: ${conflicts.first}');
  return Set.unmodifiable(directories);
}

Uint8List _immutableBytes(Uint8List bytes) => Uint8List.fromList(bytes).asUnmodifiableView();

Uint8List _boundedTransferCopy(Uint8List bytes) {
  validateCanvasTransferSize(bytes.length);
  return Uint8List.fromList(bytes).asUnmodifiableView();
}
