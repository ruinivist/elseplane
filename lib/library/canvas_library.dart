// Defines named canvases and their immutable folder hierarchy.
// Used by library operations, storage codecs, and file presentation.

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:uuid/uuid.dart';

// ---------- Entries ----------

class CanvasFile {
  const CanvasFile({
    required this.id,
    required this.name,
    this.parentId,
    this.document,
    this.githubBaseline,
  });

  final String id;
  final String name;
  final String? parentId;
  final CanvasDocument? document;
  final GitHubBaseline? githubBaseline;

  bool get isFolder => document == null;

  CanvasFile copyWith({String? name, CanvasDocument? document, GitHubBaseline? githubBaseline}) => CanvasFile(
    id: id,
    name: name ?? this.name,
    parentId: parentId,
    document: document ?? this.document,
    githubBaseline: githubBaseline ?? this.githubBaseline,
  );
}

// ---------- Library ----------

class CanvasLibrary {
  CanvasLibrary({
    required List<CanvasFile> files,
    required this.currentId,
    this.githubDestination,
    this.githubImportPromptPending = false,
  }) : files = List.unmodifiable(files);

  factory CanvasLibrary.initial([CanvasDocument? document]) {
    final file = CanvasFile(id: const Uuid().v4(), name: 'Untitled', document: document ?? emptyDocument);
    return CanvasLibrary(files: [file], currentId: file.id);
  }

  /// Validates the library structure read from or written to local storage.
  void validate() {
    final filesById = <String, CanvasFile>{};
    final ids = <String>{};
    for (final file in files) {
      if (file.id.isEmpty || file.name.trim().isEmpty || !ids.add(file.id)) {
        throw const FormatException('Invalid file name or id');
      }
      if (file.isFolder && file.githubBaseline != null) throw const FormatException('Folder has a GitHub baseline');
      filesById[file.id] = file;
    }
    for (final file in files) {
      final ancestors = <String>{file.id};
      var parent = file.parentId;
      while (parent != null) {
        if (!ancestors.add(parent)) throw const FormatException('Folder cycle');
        final folder = filesById[parent];
        if (folder == null || !folder.isFolder) throw const FormatException('Invalid parent folder');
        parent = folder.parentId;
      }
    }
    final current = filesById[currentId];
    if (current == null || current.isFolder) throw const FormatException('Current file must be a canvas');
  }

  static final emptyDocument = CanvasDocument(background: CanvasBackgroundKind.dotGrid, elements: []);

  final List<CanvasFile> files;
  final String currentId;
  final GitHubDestination? githubDestination;
  final bool githubImportPromptPending;

  CanvasFile file(String id) => files.firstWhere((file) => file.id == id);
  CanvasFile get current => file(currentId);

  List<CanvasFile> path(String id) {
    final entry = file(id);
    return [if (entry.parentId != null) ...path(entry.parentId!), entry];
  }

  String parentDirectory(String id) {
    final parentId = file(id).parentId;
    return parentId == null ? '' : path(parentId).map((entry) => entry.name).join('/');
  }

  String serializedPath(String id) {
    final canvas = file(id);
    if (canvas.isFolder) throw ArgumentError('Cannot serialize a folder as a canvas');
    final parent = parentDirectory(id);
    return parent.isEmpty ? '${canvas.name}.canvas.json' : '$parent/${canvas.name}.canvas.json';
  }

  /// Validates literal library names and their serialized transfer tree paths.
  void validatePaths() {
    final byId = <String, CanvasFile>{};
    for (final entry in files) {
      if (entry.id.isEmpty || byId.containsKey(entry.id)) {
        throw const FormatException('Invalid or duplicate library id');
      }
      byId[entry.id] = entry;
      if (entry.name.isEmpty) throw const FormatException('Empty library name');
      if (entry.name.contains('/')) throw FormatException('Invalid library name: ${entry.name}');
      validateAttachmentDirectory(entry.name);
      if (entry.isFolder && (entry.name == 'attachments' || entry.name == '.git')) {
        throw FormatException('Reserved folder name: ${entry.name}');
      }
    }

    final siblingNames = <(String?, String)>{};
    for (final entry in files) {
      if (!siblingNames.add((entry.parentId, entry.name))) {
        throw FormatException('Duplicate sibling name: ${entry.name}');
      }
      final ancestors = <String>{entry.id};
      var parentId = entry.parentId;
      while (parentId != null) {
        if (!ancestors.add(parentId)) throw const FormatException('Folder cycle');
        final parent = byId[parentId];
        if (parent == null || !parent.isFolder) throw const FormatException('Invalid parent folder');
        parentId = parent.parentId;
      }
    }

    final entries = <TransferEntry>[
      for (final entry in files)
        if (entry.isFolder)
          TransferEntry(path: path(entry.id).map((part) => part.name).join('/'), kind: TransferEntryKind.directory)
        else
          TransferEntry(path: serializedPath(entry.id), kind: TransferEntryKind.regularFile),
    ];
    validateTransferEntries(entries);
  }

  CanvasLibrary copyWith({
    List<CanvasFile>? files,
    String? currentId,
    GitHubDestination? githubDestination,
    bool? githubImportPromptPending,
  }) => CanvasLibrary(
    files: files ?? this.files,
    currentId: currentId ?? this.currentId,
    githubDestination: githubDestination ?? this.githubDestination,
    githubImportPromptPending: githubImportPromptPending ?? this.githubImportPromptPending,
  );

  CanvasLibrary replace(CanvasFile replacement) => copyWith(
    files: [
      for (final entry in files)
        if (entry.id == replacement.id) replacement else entry,
    ],
  );

  CanvasLibrary move(String id, {required String? parentId, String? beforeId}) {
    final source = file(id);
    if (parentId != null) {
      final parent = file(parentId);
      if (!parent.isFolder) throw const FormatException('Choose a folder');
      if (path(parentId).any((entry) => entry.id == id)) {
        throw const FormatException('Cannot move a folder into itself');
      }
    }
    final error = nameError(source.name, parentId, exceptId: id, isFolder: source.isFolder);
    if (error != null) throw FormatException(error);
    if (beforeId != null && (beforeId == id || file(beforeId).parentId != parentId)) {
      throw const FormatException('Invalid destination');
    }

    final siblings = files.where((entry) => entry.parentId == parentId && entry.id != id).toList();
    final siblingIndex = beforeId == null ? siblings.length : siblings.indexWhere((entry) => entry.id == beforeId);
    if (source.parentId == parentId &&
        files.where((entry) => entry.parentId == parentId).toList().indexOf(source) == siblingIndex) {
      return this;
    }

    final moved = CanvasFile(
      id: source.id,
      name: source.name,
      parentId: parentId,
      document: source.document,
      githubBaseline: source.githubBaseline,
    );
    final next = files.where((entry) => entry.id != id).toList();
    final insertAt = beforeId == null ? next.length : next.indexWhere((entry) => entry.id == beforeId);
    next.insert(insertAt, moved);
    return copyWith(files: next);
  }

  CanvasLibrary select(String id) {
    if (file(id).isFolder) throw ArgumentError('Cannot open a folder as a canvas');
    return copyWith(currentId: id);
  }

  String? nameError(String name, String? parentId, {String? exceptId, bool? isFolder}) {
    if (name.trim().isEmpty) return 'Enter a name';
    if (name.contains('/') || name.contains(r'\')) return 'Names cannot contain slashes';
    final trimmedName = name.trim();
    if (files.any((file) => file.parentId == parentId && file.id != exceptId && file.name == trimmedName)) {
      return 'This name is already in use';
    }
    final existing = exceptId == null ? null : files.where((entry) => entry.id == exceptId).firstOrNull;
    final folder = isFolder ?? existing?.isFolder ?? false;
    var candidateId = existing?.id ?? '_candidate';
    while (existing == null && files.any((entry) => entry.id == candidateId)) {
      candidateId = '_$candidateId';
    }
    final candidate = CanvasFile(
      id: candidateId,
      name: trimmedName,
      parentId: parentId,
      document: folder ? null : existing?.document ?? emptyDocument,
    );
    final candidateFiles = [
      for (final entry in files)
        if (existing == null || entry.id != existing.id) entry,
      candidate,
    ];
    try {
      copyWith(files: candidateFiles).validatePaths();
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }
}
