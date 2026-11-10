// Owns library operations, pending document revisions, and the persistence queue.
// Used by Workspace and file presentation through injected storage contracts.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/debug/demo_canvas.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_library_archive.dart';
import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

// ---------- Controller ----------

class LibraryController extends ChangeNotifier {
  LibraryController({required this._store, required this._attachments, required this._files});

  // ---------- State ----------

  final LibraryStore _store;
  final AttachmentStore _attachments;
  final CanvasProjectFiles _files;
  late CanvasLibrary _library;
  final _pending = <String, ({int revision, CanvasDocument document})>{};
  final _durableRevisions = <String, int>{};
  Future<void> _queue = Future<void>.value();
  Timer? _saveTimer;
  var _revision = 0;
  var _disposed = false;
  Object? _saveError;
  Object _documentToken = Object();

  CanvasLibrary get library => _library;
  bool get isDirty => _pending.isNotEmpty;
  Object? get saveError => _saveError;
  Object get documentToken => _documentToken;

  CanvasLibrary get snapshot {
    var result = library;
    for (final entry in _pending.entries) {
      result = result.replace(result.file(entry.key).copyWith(document: entry.value.document));
    }
    return result;
  }

  // ---------- Loading and document saves ----------

  Future<void> load() async {
    _library = await _store.load() ?? CanvasLibrary.initial();
    _notify();
  }

  void updateDocument(String fileId, CanvasDocument document) {
    if (_disposed) return;
    if (library.file(fileId).isFolder) throw ArgumentError('Cannot save a folder as a canvas');
    _pending[fileId] = (revision: ++_revision, document: document);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(
        flush().catchError((Object error) {
          _saveError = error;
          _notify();
        }),
      );
    });
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    do {
      final captured = {..._pending};
      await _enqueue(() => _saveCaptured(captured));
    } while (_pending.isNotEmpty);
  }

  Future<void> _saveCaptured(Map<String, ({int revision, CanvasDocument document})> captured) async {
    for (final entry in captured.entries) {
      final fileId = entry.key;
      final value = entry.value;
      if (value.revision <= (_durableRevisions[fileId] ?? 0)) continue;
      final next = library.replace(library.file(fileId).copyWith(document: value.document));
      await _persist(next);
      _durableRevisions[fileId] = value.revision;
      if (_pending[fileId]?.revision == value.revision) _pending.remove(fileId);
    }
    _notify();
  }

  // ---------- File operations ----------

  Future<String?> create(CanvasFile draft, {String? openId}) => _change(() async {
    if (library.files.any((file) => file.id == draft.id)) throw ArgumentError('File already exists');
    _validateName(draft.name, draft.parentId);
    var next = CanvasLibrary(
      files: [
        ...library.files,
        draft.copyWith(name: draft.name.trim()),
      ],
      currentId: library.currentId,
      githubDestination: library.githubDestination,
    );
    final selected = openId ?? (draft.isFolder ? null : draft.id);
    if (selected != null) next = next.select(selected);
    await _persist(next);
    return selected;
  });

  Future<void> rename(String id, String name, {String? openId}) => _change(() async {
    final file = library.file(id);
    _validateName(name, file.parentId, exceptId: id);
    var next = library.replace(file.copyWith(name: name.trim()));
    if (openId != null) next = next.select(openId);
    await _persist(next);
  });

  Future<void> select(String id) => _change(() => _persist(library.select(id)));

  Future<void> move(String id, {required String? parentId, String? beforeId}) => _change(() async {
    final next = library.move(id, parentId: parentId, beforeId: beforeId);
    if (!identical(next, library)) await _persist(next);
  });

  Future<String?> delete(String id) => _change(() async {
    final remaining = library.files.where((entry) => !library.path(entry.id).any((part) => part.id == id)).toList();
    if (!remaining.any((entry) => !entry.isFolder)) {
      var name = 'Untitled';
      for (
        var suffix = 2;
        remaining.any((entry) => entry.parentId == null && entry.name.toLowerCase() == name.toLowerCase());
        suffix++
      ) {
        name = 'Untitled $suffix';
      }
      remaining.add(CanvasLibrary.initial().current.copyWith(name: name));
    }
    final currentId = remaining.any((entry) => entry.id == library.currentId)
        ? library.currentId
        : remaining.firstWhere((entry) => !entry.isFolder).id;
    final changed = currentId != library.currentId;
    await _persist(CanvasLibrary(files: remaining, currentId: currentId, githubDestination: library.githubDestination));
    _discardPending(_pending.keys.where((id) => !remaining.any((file) => file.id == id)).toList());
    return changed ? currentId : null;
  });

  void _validateName(String name, String? parentId, {String? exceptId}) {
    if (parentId != null && !library.file(parentId).isFolder) throw const FormatException('Choose a folder');
    final error = library.nameError(name, parentId, exceptId: exceptId);
    if (error != null) throw FormatException(error);
  }

  Future<void> setGitHubDestination(GitHubDestination destination) => _change(() async {
    final previous = library.githubDestination;
    final sameIdentity =
        previous != null &&
        previous.accountId == destination.accountId &&
        previous.repositoryId == destination.repositoryId &&
        previous.branch == destination.branch;
    final files = sameIdentity
        ? library.files
        : [
            for (final file in library.files) file.copyWith(githubTracking: null, githubPendingTracking: null),
          ];
    await _persist(CanvasLibrary(files: files, currentId: library.currentId, githubDestination: destination));
  });

  Future<void> setGitHubTracking(
    String fileId,
    GitHubCanvasTracking? tracking, {
    GitHubCanvasTracking? pendingTracking,
  }) => _change(() async {
    final file = library.file(fileId);
    if (file.isFolder) throw ArgumentError('Cannot track a folder as a canvas');
    await _persist(
      library.replace(
        file.copyWith(githubTracking: tracking, githubPendingTracking: pendingTracking),
      ),
    );
  });

  Future<String> addGitHubCanvas({
    required List<String> folders,
    required String name,
    required CanvasProject project,
    required GitHubCanvasTracking tracking,
    String? clearPendingFileId,
  }) => _change(() async {
    [...folders, name].forEach(_validateRemoteSegment);

    final files = library.files.toList();
    String? parentId;
    for (final folderName in folders) {
      final siblings = files
          .where((file) => file.parentId == parentId && file.name.toLowerCase() == folderName.toLowerCase())
          .toList();
      if (siblings.length > 1) throw FormatException('Ambiguous folder path: $folderName');
      if (siblings.isNotEmpty) {
        final match = siblings.single;
        if (!match.isFolder) throw FormatException('A canvas blocks the folder $folderName');
        parentId = match.id;
      } else {
        final folder = CanvasFile(id: const Uuid().v4(), name: folderName, parentId: parentId);
        final error = _nameError(files, folderName, parentId);
        if (error != null) throw FormatException(error);
        files.add(folder);
        parentId = folder.id;
      }
    }
    final nameError = _nameError(files, name, parentId);
    if (nameError != null) throw FormatException(nameError);
    if (tracking.attachmentNames.keys.any((path) => !project.attachments.containsKey(path))) {
      throw const FormatException('GitHub attachment mapping does not match the canvas');
    }
    final referenced = canvasAttachmentPaths(project.document);
    if (referenced.length != project.attachments.length || !referenced.containsAll(project.attachments.keys)) {
      throw const FormatException('Canvas attachment references do not match the project');
    }

    final clearFile = clearPendingFileId == null ? null : library.file(clearPendingFileId);
    if (clearFile?.isFolder ?? false) throw ArgumentError('Cannot clear a folder write guard');
    final id = const Uuid().v4();
    await _stage(project.attachments, (replacements) {
      final rebasedTracking = GitHubCanvasTracking(
        path: tracking.path,
        documentSha: tracking.documentSha,
        attachmentShas: tracking.attachmentShas,
        attachmentNames: {
          for (final entry in tracking.attachmentNames.entries) replacements[entry.key]!: entry.value,
        },
      );
      final stagedFile = CanvasFile(
        id: id,
        name: name,
        parentId: parentId,
        document: rebaseCanvasDocumentAttachments(project.document, replacements),
        githubTracking: rebasedTracking,
      );
      return CanvasLibrary(
        files: [
          for (final file in files)
            if (clearFile != null && file.id == clearFile.id) file.copyWith(githubPendingTracking: null) else file,
          stagedFile,
        ],
        currentId: id,
        githubDestination: library.githubDestination,
      );
    });
    return id;
  });

  String? _nameError(List<CanvasFile> files, String name, String? parentId) {
    if (name.trim().isEmpty) return 'Enter a name';
    if (files.any(
      (file) => file.parentId == parentId && file.name.toLowerCase() == name.trim().toLowerCase(),
    )) {
      return 'This name is already in use';
    }
    return null;
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

  // ---------- Transfers ----------

  Future<CanvasProject?> readProject() async {
    final bytes = await _files.open();
    return bytes == null ? null : await decodeCanvasProject(bytes);
  }

  Future<CanvasLibraryArchive?> readArchive() async {
    final bytes = await _files.open();
    return bytes == null ? null : await decodeCanvasLibraryArchive(bytes);
  }

  Future<bool> exportCanvas(String fileId) async {
    final document = snapshot.file(fileId).document!;
    final bytes = await encodeCanvasProject(document, _attachments);
    return await _files.save(bytes, suggestedName: 'canvas.elseplane.zip', mimeType: 'application/zip');
  }

  Future<bool> backup() async {
    final captured = snapshot;
    final bytes = await encodeCanvasLibraryArchive(captured, _attachments);
    return await _files.save(bytes, suggestedName: 'library.elseplane.zip', mimeType: 'application/zip');
  }

  Future<void> replaceCanvas(String fileId, CanvasProject project) => _change(() async {
    await _stage(project.attachments, (replacements) {
      final document = rebaseCanvasDocumentAttachments(project.document, replacements);
      return library.replace(
        library
            .file(fileId)
            .copyWith(
              document: document,
              githubTracking: null,
              githubPendingTracking: null,
            ),
      );
    });
    _discardPending([fileId]);
  });

  Future<void> restore(CanvasLibraryArchive archive) => _change(() async {
    await _stage(
      archive.attachments,
      (replacements) => CanvasLibrary(
        files: [
          for (final file in archive.library.files)
            file.copyWith(
              document: file.isFolder ? null : rebaseCanvasDocumentAttachments(file.document!, replacements),
              githubTracking: null,
              githubPendingTracking: null,
            ),
        ],
        currentId: archive.library.currentId,
      ),
    );
    _discardPending(_pending.keys.toList());
  });

  Future<String> createDemo() => _change(() async {
    if (!kDebugMode) throw UnsupportedError('Demo is only available in debug builds');
    final project = await loadDemoCanvas();
    var name = 'Demo';
    for (var suffix = 2; library.nameError(name, null) != null; suffix++) {
      name = 'Demo $suffix';
    }
    final id = const Uuid().v4();
    await _stage(
      project.attachments,
      (replacements) => CanvasLibrary(
        files: [
          ...library.files,
          CanvasFile(id: id, name: name, document: rebaseCanvasDocumentAttachments(project.document, replacements)),
        ],
        currentId: id,
        githubDestination: library.githubDestination,
      ),
    );
    return id;
  });

  /// Prepares fresh bytes before publishing their references in one metadata write.
  /// Used by canvas import, library restore, and debug demo creation.
  Future<void> _stage(Map<String, Uint8List> attachments, CanvasLibrary Function(Map<String, String>) build) async {
    final replacements = <String, String>{};
    final reserved = attachments.keys.toSet();
    for (final path in attachments.keys.toList()..sort()) {
      String fresh;
      do {
        fresh = 'attachments/${const Uuid().v4()}.${path.split('.').last}';
      } while (reserved.contains(fresh) || await _attachments.readIfExists(fresh) != null);
      reserved.add(fresh);
      replacements[path] = fresh;
    }
    final next = build(replacements);
    final attempted = <String>[];
    try {
      for (final entry in replacements.entries) {
        attempted.add(entry.value);
        await _attachments.write(entry.value, attachments[entry.key]!);
      }
      await _persist(next, replaceDocument: true);
    } on Object {
      for (final path in attempted) {
        try {
          await _attachments.delete(path);
        } on Object catch (error) {
          debugPrint('Could not remove staged attachment $path: $error');
        }
      }
      rethrow;
    }
  }

  // ---------- Queue and lifetime ----------

  Future<T> _change<T>(Future<T> Function() operation) {
    _saveTimer?.cancel();
    _saveTimer = null;
    return _enqueue(() async {
      while (_pending.isNotEmpty) {
        await _saveCaptured({..._pending});
      }
      final result = await operation();
      _notify();
      return result;
    });
  }

  void _discardPending(Iterable<String> ids) {
    for (final id in ids) {
      _durableRevisions[id] = _revision;
      _pending.remove(id);
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object error, StackTrace stackTrace) {});
    return result;
  }

  Future<void> _persist(CanvasLibrary next, {bool replaceDocument = false}) async {
    await _store.save(next);
    if (replaceDocument || next.currentId != library.currentId) _documentToken = Object();
    _library = next;
    _saveError = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    unawaited(flush().catchError((Object error) => debugPrint('Could not save canvas on disposal: $error')));
    super.dispose();
  }
}
