// Defines named canvases and their immutable folder hierarchy.
// Used by library operations, storage codecs, and file presentation.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:uuid/uuid.dart';

// ---------- Entries ----------

class CanvasFile {
  const CanvasFile({required this.id, required this.name, this.parentId, this.document});

  factory CanvasFile.fromJson(Map<String, dynamic> json) => CanvasFile(
    id: json['id'] as String,
    name: json['name'] as String,
    parentId: json['parentId'] as String?,
    document: json['document'] == null ? null : CanvasDocument.fromJson(json['document']),
  );

  final String id;
  final String name;
  final String? parentId;
  final CanvasDocument? document;

  bool get isFolder => document == null;

  CanvasFile copyWith({String? name, CanvasDocument? document}) => CanvasFile(
    id: id,
    name: name ?? this.name,
    parentId: parentId,
    document: document ?? this.document,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'document': document?.toJson(),
  };
}

// ---------- Library ----------

class CanvasLibrary {
  CanvasLibrary({required List<CanvasFile> files, required this.currentId}) : files = List.unmodifiable(files);

  factory CanvasLibrary.initial([CanvasDocument? document]) {
    final file = CanvasFile(id: const Uuid().v4(), name: 'Untitled', document: document ?? emptyDocument);
    return CanvasLibrary(files: [file], currentId: file.id);
  }

  factory CanvasLibrary.fromJson(Object? source) {
    if (source is! Map<String, dynamic> || source['version'] != 1 || source['files'] is! List) {
      throw const FormatException('Invalid canvas library');
    }
    final library = CanvasLibrary(
      files: (source['files'] as List<dynamic>)
          .map((file) => CanvasFile.fromJson(file as Map<String, dynamic>))
          .toList(),
      currentId: source['currentId'] as String,
    );
    final ids = <String>{};
    for (final file in library.files) {
      if (file.id.isEmpty || file.name.trim().isEmpty || !ids.add(file.id)) {
        throw const FormatException('Invalid file name or id');
      }
      final ancestors = <String>{file.id};
      var parent = file.parentId;
      while (parent != null) {
        if (!ancestors.add(parent)) throw const FormatException('Folder cycle');
        final folder = library.file(parent);
        if (!folder.isFolder) throw const FormatException('Invalid parent folder');
        parent = folder.parentId;
      }
    }
    if (library.current.isFolder) throw const FormatException('Current file must be a canvas');
    return library;
  }

  static final emptyDocument = CanvasDocument(background: CanvasBackgroundKind.dotGrid, elements: []);

  final List<CanvasFile> files;
  final String currentId;

  CanvasFile file(String id) => files.firstWhere((file) => file.id == id);
  CanvasFile get current => file(currentId);

  List<CanvasFile> path(String id) {
    final entry = file(id);
    return [if (entry.parentId != null) ...path(entry.parentId!), entry];
  }

  CanvasLibrary replace(CanvasFile replacement) => CanvasLibrary(
    files: [
      for (final entry in files)
        if (entry.id == replacement.id) replacement else entry,
    ],
    currentId: currentId,
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
    final error = nameError(source.name, parentId, exceptId: id);
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

    final moved = CanvasFile(id: source.id, name: source.name, parentId: parentId, document: source.document);
    final next = files.where((entry) => entry.id != id).toList();
    final insertAt = beforeId == null ? next.length : next.indexWhere((entry) => entry.id == beforeId);
    next.insert(insertAt, moved);
    return CanvasLibrary(files: next, currentId: currentId);
  }

  CanvasLibrary select(String id) {
    if (file(id).isFolder) throw ArgumentError('Cannot open a folder as a canvas');
    return CanvasLibrary(files: files, currentId: id);
  }

  String? nameError(String name, String? parentId, {String? exceptId}) {
    if (name.trim().isEmpty) return 'Enter a name';
    if (name.contains('/') || name.contains(r'\')) return 'Names cannot contain slashes';
    if (files.any(
      (file) =>
          file.parentId == parentId && file.id != exceptId && file.name.toLowerCase() == name.trim().toLowerCase(),
    )) {
      return 'This name is already in use';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'currentId': currentId,
    'files': files.map((file) => file.toJson()).toList(),
  };
}
