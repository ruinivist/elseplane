// Owns library operations, pending document revisions, and the persistence queue.
// Used by Workspace and file presentation through injected storage contracts.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/attachment_references.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/debug/demo_canvas.dart';
import 'package:elseplane/library/github_metadata.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/library/transfer/canvas_transfer_zip.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

const _transferCanvasSuffix = '.canvas.json';

// ---------- Controller ----------

class LibraryController extends ChangeNotifier {
  LibraryController({
    required LibraryStore store,
    required AttachmentStore attachments,
    required CanvasProjectFiles files,
    this.onAttachmentPathsChanged,
  }) : // Public names cannot use private initializing formals.
       // Public named parameters must stay separate from private fields.
       // ignore: prefer_initializing_formals
       _store = store,
       // Public names cannot use private initializing formals.
       // ignore: prefer_initializing_formals
       _attachments = attachments,
       // Public names cannot use private initializing formals.
       // ignore: prefer_initializing_formals
       _files = files;

  // ---------- State ----------

  final LibraryStore _store;
  final AttachmentStore _attachments;
  final CanvasProjectFiles _files;
  final void Function(Set<String> paths)? onAttachmentPathsChanged;
  late CanvasLibrary _library;
  final _pending = <String, ({int revision, CanvasDocument document})>{};
  final _durableRevisions = <String, int>{};
  Future<void> _queue = Future<void>.value();
  Timer? _saveTimer;
  var _revision = 0;
  var _changeRevision = 0;
  var _hasDurableLibrary = false;
  var _disposed = false;
  Object? _saveError;
  Object _documentToken = Object();

  CanvasLibrary get library => _library;
  bool get isDirty => _pending.isNotEmpty;
  Object? get saveError => _saveError;
  Object get documentToken => _documentToken;
  int get changeRevision => _changeRevision;

  CanvasLibrary get snapshot {
    var result = library;
    for (final entry in _pending.entries) {
      result = result.replace(result.file(entry.key).copyWith(document: entry.value.document));
    }
    return result;
  }

  // ---------- Loading and document saves ----------

  Future<void> load() async {
    final saved = await _store.load();
    _library = saved ?? CanvasLibrary.initial();
    _hasDurableLibrary = saved != null;
    _changeRevision++;
    _notify();
  }

  void updateDocument(String fileId, CanvasDocument document) {
    if (_disposed) return;
    if (library.file(fileId).isFolder) throw ArgumentError('Cannot save a folder as a canvas');
    _pending[fileId] = (revision: ++_revision, document: document);
    _changeRevision++;
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
    _validateName(draft.name, draft.parentId, isFolder: draft.isFolder);
    var next = library.copyWith(
      files: [
        ...library.files,
        draft.copyWith(name: draft.name.trim()),
      ],
    );
    final selected = openId ?? (draft.isFolder ? null : draft.id);
    if (selected != null) next = next.select(selected);
    await _persist(next);
    return selected;
  });

  Future<void> rename(String id, String name, {String? openId}) => _change(() async {
    final file = library.file(id);
    _validateName(name, file.parentId, exceptId: id, isFolder: file.isFolder);
    var next = library.replace(file.copyWith(name: name.trim()));
    if (openId != null) next = next.select(openId);
    await _persistHierarchy(next);
  });

  Future<void> select(String id) => _change(() => _persist(library.select(id)));

  Future<void> move(String id, {required String? parentId, String? beforeId}) => _change(() async {
    final next = library.move(id, parentId: parentId, beforeId: beforeId);
    if (!identical(next, library)) await _persistHierarchy(next);
  });

  Future<String?> delete(String id) => _change(() async {
    final remaining = library.files.where((entry) => !library.path(entry.id).any((part) => part.id == id)).toList();
    if (!remaining.any((entry) => !entry.isFolder)) {
      var name = 'Untitled';
      for (var suffix = 2; remaining.any((entry) => entry.parentId == null && entry.name == name); suffix++) {
        name = 'Untitled $suffix';
      }
      remaining.add(CanvasLibrary.initial().current.copyWith(name: name));
    }
    final currentId = remaining.any((entry) => entry.id == library.currentId)
        ? library.currentId
        : remaining.firstWhere((entry) => !entry.isFolder).id;
    final changed = currentId != library.currentId;
    await _persist(library.copyWith(files: remaining, currentId: currentId));
    _discardPending(_pending.keys.where((id) => !remaining.any((file) => file.id == id)).toList());
    return changed ? currentId : null;
  });

  void _validateName(String name, String? parentId, {required bool isFolder, String? exceptId}) {
    if (parentId != null && !library.file(parentId).isFolder) throw const FormatException('Choose a folder');
    final error = library.nameError(name, parentId, exceptId: exceptId, isFolder: isFolder);
    if (error != null) throw FormatException(error);
  }

  Future<void> setGitHubDestination(GitHubDestination destination) => _change(() async {
    await _persist(
      library.copyWith(
        githubDestination: destination,
        githubImportPromptPending: library.githubDestination == null || library.githubImportPromptPending,
      ),
    );
  });

  Future<void> dismissGitHubImportPrompt() => _change(() async {
    if (!library.githubImportPromptPending) return;
    await _persist(library.copyWith(githubImportPromptPending: false));
  });

  Future<void> saveGitHubBaseline(String fileId, GitHubBaseline baseline) =>
      _change(() => _persist(library.replace(library.file(fileId).copyWith(githubBaseline: baseline))));

  // ---------- Transfers ----------

  Future<TransferSource?> readTransferSource() async {
    final selected = await _files.open();
    return selected == null ? null : transferSourceFromFile(name: selected.name, bytes: selected.bytes);
  }

  Future<TransferMerge> previewTransferImport(TransferImport candidate) async {
    await flush();
    final current = library;
    final preview = _mergeTransferCandidate(current, candidate);
    preview.library.validatePaths();
    return TransferMerge(
      candidate: candidate,
      expectedChangeRevision: changeRevision,
      overwritePaths: preview.overwritePaths,
    );
  }

  Future<TransferImportResult> importTransfer(
    TransferMerge merge, {
    required Set<String> confirmedOverwritePaths,
    GitHubDestination? githubDestination,
  }) {
    final confirmedPaths = Set<String>.of(confirmedOverwritePaths);
    TransferImportResult result({
      required List<String> written,
      required bool saved,
      TransferFailure? failure,
    }) => TransferImportResult(
      skippedCanvases: merge.candidate.skippedCanvases,
      writtenImagePaths: written,
      metadataSaved: saved,
      failure: failure,
    );
    return _change(() async {
      if (changeRevision != merge.expectedChangeRevision) {
        return result(
          written: const [],
          saved: false,
          failure: const TransferFailure(
            reason: 'Library changed since preview',
            stage: TransferFailureStage.preparation,
          ),
        );
      }

      late final _TransferCandidateMerge prepared;
      late final Map<String, Uint8List> eligibleImages;
      try {
        prepared = _mergeTransferCandidate(library, merge.candidate, githubDestination: githubDestination);
        prepared.library.validatePaths();
        eligibleImages = _eligibleTransferImages(merge.candidate);
      } on FormatException {
        return result(
          written: const [],
          saved: false,
          failure: const TransferFailure(
            reason: 'Invalid transfer hierarchy',
            stage: TransferFailureStage.preparation,
          ),
        );
      }

      if (!_samePaths(merge.overwritePaths, prepared.overwritePaths) ||
          !_samePaths(confirmedPaths, prepared.overwritePaths)) {
        return result(
          written: const [],
          saved: false,
          failure: const TransferFailure(
            reason: 'Overwrite confirmation does not match preview',
            stage: TransferFailureStage.preparation,
          ),
        );
      }

      final written = <String>[];
      final affected = <String>{};
      try {
        for (final path in eligibleImages.keys.toList()..sort()) {
          affected.add(path);
          try {
            await _attachments.write(path, eligibleImages[path]!);
          } on Object {
            return result(
              written: written,
              saved: false,
              failure: TransferFailure(
                reason: 'Image write failed',
                path: path,
                stage: TransferFailureStage.imageWrite,
              ),
            );
          }
          written.add(path);
        }

        if (changeRevision != merge.expectedChangeRevision) {
          return result(
            written: written,
            saved: false,
            failure: const TransferFailure(
              reason: 'Library changed during import',
              stage: TransferFailureStage.publication,
            ),
          );
        }

        if (!prepared.changed) return result(written: written, saved: false);

        final replacedIds = prepared.overwritePaths
            .map((path) => prepared.existingCanvasIds[path])
            .whereType<String>()
            .toList();
        final activeOverwritten = prepared.overwritePaths.contains(library.serializedPath(library.currentId));
        try {
          await _persist(prepared.library, replaceDocument: activeOverwritten);
        } on Object {
          return result(
            written: written,
            saved: false,
            failure: const TransferFailure(
              reason: 'Library save failed',
              stage: TransferFailureStage.publication,
            ),
          );
        }
        _discardPending(replacedIds);
        return result(written: written, saved: true);
      } finally {
        if (affected.isNotEmpty) onAttachmentPathsChanged?.call(Set.unmodifiable(affected));
      }
    });
  }

  _TransferCandidateMerge _mergeTransferCandidate(
    CanvasLibrary current,
    TransferImport candidate, {
    GitHubDestination? githubDestination,
  }) {
    current.validatePaths();
    final folderIds = <String, String>{};
    final existingCanvasIds = <String, String>{};
    for (final file in current.files) {
      if (file.isFolder) {
        folderIds[current.path(file.id).map((part) => part.name).join('/')] = file.id;
      } else {
        existingCanvasIds[current.serializedPath(file.id)] = file.id;
      }
    }

    final directoryPaths = <String>{};
    void addDirectoryAndParents(String path) {
      final segments = path.split('/');
      for (var length = 1; length <= segments.length; length++) {
        directoryPaths.add(segments.take(length).join('/'));
      }
    }

    candidate.directories.forEach(addDirectoryAndParents);
    for (final path in candidate.canvases.keys) {
      if (!path.endsWith(_transferCanvasSuffix)) throw FormatException('Invalid canvas path: $path');
      final segments = path.split('/');
      if (segments.length > 1) addDirectoryAndParents(segments.take(segments.length - 1).join('/'));
    }

    final files = current.files.toList();
    final usedIds = files.map((file) => file.id).toSet();
    var changed = false;
    final orderedDirectories = directoryPaths.toList()
      ..sort((a, b) {
        final depth = a.split('/').length.compareTo(b.split('/').length);
        return depth != 0 ? depth : a.compareTo(b);
      });
    for (final path in orderedDirectories) {
      if (folderIds.containsKey(path)) continue;
      final segments = path.split('/');
      final parentPath = segments.length == 1 ? '' : segments.take(segments.length - 1).join('/');
      final parentId = parentPath.isEmpty ? null : folderIds[parentPath];
      if (parentPath.isNotEmpty && parentId == null) throw FormatException('Invalid folder path: $path');
      final id = _newLocalId(usedIds);
      usedIds.add(id);
      files.add(CanvasFile(id: id, name: segments.last, parentId: parentId));
      folderIds[path] = id;
      changed = true;
    }

    final overwritePaths = <String>{};
    for (final path in candidate.canvases.keys.toList()..sort()) {
      final segments = path.split('/');
      final filename = segments.last;
      final name = filename.substring(0, filename.length - _transferCanvasSuffix.length);
      if (name.isEmpty || name.trim().isEmpty) throw FormatException('Invalid canvas path: $path');
      final parentPath = segments.length == 1 ? '' : segments.take(segments.length - 1).join('/');
      final parentId = parentPath.isEmpty ? null : folderIds[parentPath];
      if (parentPath.isNotEmpty && parentId == null) throw FormatException('Invalid canvas path: $path');
      final existingId = existingCanvasIds[path];
      final document = candidate.canvases[path]!;
      final baseline = githubDestination == null
          ? null
          : GitHubBaseline.capture(githubDestination, path, document, candidate.attachments);
      if (existingId != null) {
        final index = files.indexWhere((file) => file.id == existingId);
        files[index] = files[index].copyWith(document: document, githubBaseline: baseline);
        overwritePaths.add(path);
      } else {
        final id = _newLocalId(usedIds);
        usedIds.add(id);
        files.add(CanvasFile(id: id, name: name, parentId: parentId, document: document, githubBaseline: baseline));
      }
      changed = true;
    }

    return _TransferCandidateMerge(
      library: current.copyWith(files: files),
      overwritePaths: Set.unmodifiable(overwritePaths),
      existingCanvasIds: Map.unmodifiable(existingCanvasIds),
      changed: changed,
    );
  }

  Map<String, Uint8List> _eligibleTransferImages(TransferImport candidate) {
    for (final entry in candidate.attachments.entries) {
      validateAttachmentPath(entry.key);
      validateAttachmentSize(entry.value.length, 'Attachment exceeds 10 MiB: ${entry.key}');
    }

    final referenced = <String>{};
    for (final entry in candidate.canvases.entries) {
      final segments = entry.key.split('/');
      final parent = segments.length == 1 ? '' : segments.take(segments.length - 1).join('/');
      for (final reference in canvasAttachmentPaths(entry.value.elements)) {
        referenced.add(resolveAttachmentPath(parent, reference));
      }
    }
    return {
      for (final entry in candidate.attachments.entries)
        if (referenced.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<void> _persistHierarchy(CanvasLibrary next) async {
    final attempted = <String>{};
    try {
      await copyAttachmentPaths(
        _attachments,
        _hierarchyAttachmentCopies(library, next),
        beforeWrite: attempted.add,
      );
      await _persist(next);
    } finally {
      if (attempted.isNotEmpty) onAttachmentPathsChanged?.call(Set.unmodifiable(attempted));
    }
  }

  Map<String, String> _hierarchyAttachmentCopies(CanvasLibrary before, CanvasLibrary after) {
    final copies = <String, String>{};
    for (final oldCanvas in before.files.where((file) => !file.isFolder)) {
      final newCanvas = after.files.where((file) => file.id == oldCanvas.id).firstOrNull;
      if (newCanvas == null || newCanvas.isFolder) continue;
      final oldParent = before.parentDirectory(oldCanvas.id);
      final newParent = after.parentDirectory(newCanvas.id);
      if (oldParent == newParent) continue;
      for (final reference in canvasAttachmentPaths(oldCanvas.document!.elements)) {
        final source = resolveAttachmentPath(oldParent, reference);
        final destination = resolveAttachmentPath(newParent, reference);
        if (source != destination) copies[source] = destination;
      }
    }
    return copies;
  }

  String _newLocalId(Set<String> usedIds) {
    String id;
    do {
      id = const Uuid().v4();
    } while (usedIds.contains(id));
    return id;
  }

  bool _samePaths(Set<String> first, Set<String> second) => first.length == second.length && first.containsAll(second);

  Future<bool> exportCanvas(String fileId) async {
    final captured = snapshot.select(fileId);
    final tree = await encodeTransfer(captured, _attachments, TransferScope.currentCanvas);
    final bytes = encodeTransferZip(tree);
    return await _files.save(bytes, suggestedName: 'canvas.elseplane.zip', mimeType: 'application/zip');
  }

  Future<bool> exportLibrary() async {
    final captured = snapshot;
    final tree = await encodeTransfer(captured, _attachments, TransferScope.wholeLibrary);
    final bytes = encodeTransferZip(tree);
    return await _files.save(bytes, suggestedName: 'library.elseplane.zip', mimeType: 'application/zip');
  }

  Future<String> createDemo() => _change(() async {
    if (!kDebugMode) throw UnsupportedError('Demo is only available in debug builds');
    final demo = await loadDemoCanvas();
    var name = 'Demo';
    for (var suffix = 2; library.nameError(name, null) != null; suffix++) {
      name = 'Demo $suffix';
    }
    final usedIds = library.files.map((file) => file.id).toSet();
    final id = _newLocalId(usedIds);
    final document = demo.canvases['Demo.canvas.json']!;
    final images = _eligibleTransferImages(demo);
    final attempted = <String>{};
    try {
      for (final path in images.keys.toList()..sort()) {
        attempted.add(path);
        await _attachments.write(path, images[path]!);
      }
      await _persist(
        library.copyWith(
          files: [
            ...library.files,
            CanvasFile(id: id, name: name, document: document),
          ],
          currentId: id,
        ),
        replaceDocument: true,
      );
      return id;
    } finally {
      if (attempted.isNotEmpty) onAttachmentPathsChanged?.call(Set.unmodifiable(attempted));
    }
  });

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
    await _store.save(next, previous: _hasDurableLibrary ? library : null);
    if (replaceDocument || next.currentId != library.currentId) _documentToken = Object();
    _library = next;
    _hasDurableLibrary = true;
    _changeRevision++;
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

final class _TransferCandidateMerge {
  const _TransferCandidateMerge({
    required this.library,
    required this.overwritePaths,
    required this.existingCanvasIds,
    required this.changed,
  });

  final CanvasLibrary library;
  final Set<String> overwritePaths;
  final Map<String, String> existingCanvasIds;
  final bool changed;
}
