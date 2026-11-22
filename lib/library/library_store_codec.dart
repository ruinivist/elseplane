// Encodes IndexedDB library records without involving browser APIs.

import 'dart:convert';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/github_metadata.dart';

final class LibraryStoreWriteSet {
  const LibraryStoreWriteSet({
    required this.metadata,
    required this.documentPuts,
    required this.documentDeletes,
  });

  /// The replacement metadata record, or null when metadata is unchanged.
  final String? metadata;
  final Map<String, String> documentPuts;
  final List<String> documentDeletes;

  bool get isEmpty => metadata == null && documentPuts.isEmpty && documentDeletes.isEmpty;
}

abstract final class LibraryStoreCodec {
  static const metadataVersion = 1;

  static LibraryStoreWriteSet calculateWrites(CanvasLibrary? previous, CanvasLibrary next) {
    next.validate();

    final oldCanvases = {
      if (previous != null)
        for (final file in previous.files)
          if (!file.isFolder) file.id: file,
    };
    final newCanvases = {
      for (final file in next.files)
        if (!file.isFolder) file.id: file,
    };
    final documentPuts = <String, String>{};
    for (final entry in newCanvases.entries) {
      final oldDocument = oldCanvases[entry.key]?.document;
      final document = entry.value.document!;
      if (previous == null || !identical(oldDocument, document)) {
        documentPuts[entry.key] = jsonEncode(document.toJson());
      }
    }

    final documentDeletes = [
      for (final id in oldCanvases.keys)
        if (!newCanvases.containsKey(id)) id,
    ];
    return LibraryStoreWriteSet(
      metadata: previous == null || !_sameMetadata(previous, next) ? encodeMetadata(next) : null,
      documentPuts: Map.unmodifiable(documentPuts),
      documentDeletes: List.unmodifiable(documentDeletes),
    );
  }

  /// Callers must validate [library] before encoding it.
  static String encodeMetadata(CanvasLibrary library) {
    return jsonEncode({
      'version': metadataVersion,
      'currentId': library.currentId,
      'githubDestination': library.githubDestination?.toJson(),
      'githubImportPromptPending': library.githubImportPromptPending,
      'entries': [
        for (final file in library.files)
          {
            'id': file.id,
            'name': file.name,
            'parentId': file.parentId,
            'kind': file.isFolder ? 'folder' : 'canvas',
            if (file.githubBaseline != null) 'githubBaseline': file.githubBaseline!.toJson(),
          },
      ],
    });
  }

  static CanvasLibrary decodeRecords(String metadataRecord, Map<String, String> documentRecords) {
    final metadata = _object(jsonDecode(metadataRecord), 'library metadata');
    _checkExactKeys(metadata, const [
      'version',
      'currentId',
      'githubDestination',
      'githubImportPromptPending',
      'entries',
    ]);
    if (metadata['version'] is! int || metadata['version'] != metadataVersion) {
      throw const FormatException('Invalid library metadata version');
    }
    final currentId = _string(metadata['currentId'], 'currentId');
    final importPromptPending = metadata['githubImportPromptPending'];
    if (importPromptPending is! bool) throw const FormatException('Invalid GitHub import prompt state');
    final rawEntries = metadata['entries'];
    if (rawEntries is! List) throw const FormatException('Library entries must be a list');

    final entries = <_LibraryEntry>[];
    final canvasIds = <String>{};
    for (final rawEntry in rawEntries) {
      final entry = _object(rawEntry, 'library entry');
      _checkKeys(entry, const ['id', 'name', 'parentId', 'kind'], const ['githubBaseline']);
      final id = _string(entry['id'], 'entry id');
      final name = _string(entry['name'], 'entry name');
      final rawParentId = entry['parentId'];
      if (rawParentId != null && rawParentId is! String) {
        throw const FormatException('Invalid library parent id');
      }
      final kind = entry['kind'];
      if (kind != 'canvas' && kind != 'folder') throw const FormatException('Invalid library entry kind');
      final rawBaseline = entry['githubBaseline'];
      if (entry.containsKey('githubBaseline') && rawBaseline == null) {
        throw const FormatException('Invalid GitHub baseline');
      }
      final baseline = rawBaseline == null ? null : GitHubBaseline.fromJson(rawBaseline);
      if (kind == 'folder' && baseline != null) {
        throw const FormatException('Folder has a GitHub baseline');
      }
      if (kind == 'canvas') canvasIds.add(id);
      entries.add(
        _LibraryEntry(
          id,
          name,
          rawParentId as String?,
          isCanvas: kind == 'canvas',
          githubBaseline: baseline,
        ),
      );
    }
    if (canvasIds.length != entries.where((entry) => entry.isCanvas).length ||
        !canvasIds.containsAll(documentRecords.keys) ||
        !documentRecords.keys.toSet().containsAll(canvasIds)) {
      throw const FormatException('Library canvas records do not match metadata');
    }

    final files = [
      for (final entry in entries)
        CanvasFile(
          id: entry.id,
          name: entry.name,
          parentId: entry.parentId,
          document: entry.isCanvas ? _decodeDocument(documentRecords[entry.id]!) : null,
          githubBaseline: entry.githubBaseline,
        ),
    ];
    final destination = metadata['githubDestination'];
    final library = CanvasLibrary(
      files: files,
      currentId: currentId,
      githubDestination: destination == null ? null : GitHubDestination.fromJson(destination),
      githubImportPromptPending: importPromptPending,
    )..validate();
    return library;
  }

  static CanvasDocument _decodeDocument(String source) => CanvasDocument.fromJson(jsonDecode(source));

  static bool _sameMetadata(CanvasLibrary left, CanvasLibrary right) {
    if (left.currentId != right.currentId ||
        left.githubImportPromptPending != right.githubImportPromptPending ||
        !_sameDestination(left.githubDestination, right.githubDestination) ||
        left.files.length != right.files.length) {
      return false;
    }
    for (var index = 0; index < left.files.length; index++) {
      final a = left.files[index];
      final b = right.files[index];
      if (a.id != b.id ||
          a.name != b.name ||
          a.parentId != b.parentId ||
          a.isFolder != b.isFolder ||
          !_sameBaseline(a.githubBaseline, b.githubBaseline)) {
        return false;
      }
    }
    return true;
  }

  static bool _sameDestination(GitHubDestination? left, GitHubDestination? right) =>
      identical(left, right) ||
      left != null &&
          right != null &&
          left.accountId == right.accountId &&
          left.repositoryId == right.repositoryId &&
          left.owner == right.owner &&
          left.repository == right.repository &&
          left.branch == right.branch;

  static bool _sameBaseline(GitHubBaseline? left, GitHubBaseline? right) {
    if (identical(left, right)) return true;
    if (left == null ||
        right == null ||
        !_sameDestination(left.destination, right.destination) ||
        left.path != right.path ||
        left.documentHash != right.documentHash ||
        left.attachmentHashes.length != right.attachmentHashes.length) {
      return false;
    }
    return left.attachmentHashes.entries.every((entry) => right.attachmentHashes[entry.key] == entry.value);
  }
}

final class _LibraryEntry {
  const _LibraryEntry(
    this.id,
    this.name,
    this.parentId, {
    required this.isCanvas,
    required this.githubBaseline,
  });

  final String id;
  final String name;
  final String? parentId;
  final bool isCanvas;
  final GitHubBaseline? githubBaseline;
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$field must be an object with string keys');
  }
  return value.cast<String, dynamic>();
}

void _checkExactKeys(Map<String, dynamic> value, List<String> keys) {
  if (value.length != keys.length || value.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('Invalid library metadata fields');
  }
}

void _checkKeys(Map<String, dynamic> value, List<String> requiredKeys, [List<String> optional = const []]) {
  final allowed = {...requiredKeys, ...optional};
  if (requiredKeys.any((key) => !value.containsKey(key)) || value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Invalid library entry fields');
  }
}

String _string(Object? value, String field) {
  if (value is! String) throw FormatException('Invalid library $field');
  return value;
}
