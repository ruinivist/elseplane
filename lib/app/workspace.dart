// Connects the canvas editor lifetime to library durability and file presentation.
// Used by the root app to compose injected storage, editor snapshots, and settings actions.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:elseplane/library/widgets/canvas_file_picker.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/surface_dialog.dart';
import 'package:flutter/material.dart';

// ---------- Workspace ----------

class Workspace extends StatefulWidget {
  const Workspace({
    required this.libraryStore,
    required this.attachmentStore,
    required this.projectFiles,
    this.readClipboard,
    this.writeClipboardText,
    this.themeMode = ThemeMode.light,
    this.onSurfaceStyleChanged,
    this.onThemeModeChanged,
    super.key,
  });

  final LibraryStore libraryStore;
  final AttachmentStore attachmentStore;
  final CanvasProjectFiles projectFiles;
  final Future<CanvasClipboardSnapshot> Function()? readClipboard;
  final Future<void> Function(String text)? writeClipboardText;
  final ThemeMode themeMode;
  final Future<void> Function(SurfaceStyle)? onSurfaceStyleChanged;
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  // ---------- Lifetime ----------

  late final _library = LibraryController(
    store: widget.libraryStore,
    attachments: widget.attachmentStore,
    files: widget.projectFiles,
  );
  final _replacement = ValueNotifier<CanvasReplacement>((document: null, token: Object()));
  String? _fileId;
  Object? _reportedSaveError;
  var _blocked = false;
  var _transferActive = false;

  @override
  void initState() {
    super.initState();
    _library.addListener(_libraryChanged);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _library.load();
      if (mounted) _replaceEditor();
    } on Object {
      if (mounted) _showMessage('Could not load saved canvas');
    }
  }

  void _libraryChanged() {
    if (!mounted) return;
    final error = _library.saveError;
    if (error != null && !identical(error, _reportedSaveError)) _showMessage('Could not save canvas');
    _reportedSaveError = error;
    setState(() {});
  }

  void _replaceEditor() => setState(() {
    _fileId = _library.library.currentId;
    _replacement.value = (document: _library.library.current.document, token: _library.documentToken);
  });

  @override
  void dispose() {
    _replacement.dispose();
    _library
      ..removeListener(_libraryChanged)
      ..dispose();
    super.dispose();
  }

  // ---------- File presentation ----------

  Future<void> _showLibrary() async {
    if (_replacement.value.document == null || _transferActive || _blocked) return;
    setState(() => _blocked = true);
    try {
      await _library.flush();
      if (!mounted) return;
      final selectedId = await showDialog<String>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) => CanvasFilePicker(controller: _library),
      );
      if (mounted && selectedId != null && selectedId != _fileId) _replaceEditor();
    } on Object {
      _showMessage('Could not open canvas. Your current canvas is still open.');
    } finally {
      if (mounted) setState(() => _blocked = false);
    }
  }

  Future<bool> _confirmReplacement({required String title, required String message, required String action}) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => SurfaceConfirmationDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _replace(Future<void> Function() commit) async {
    setState(() => _blocked = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _library.flush();
      if (!mounted) return;
      await commit();
      if (mounted) _replaceEditor();
    } finally {
      if (mounted) setState(() => _blocked = false);
    }
  }

  // ---------- Settings transfers ----------

  Future<void> _exportCanvas() async {
    if (_transferActive || _fileId == null) return;
    _transferActive = true;
    try {
      if (await _library.exportCanvas(_fileId!)) _showMessage('Canvas exported');
    } on Object {
      _showMessage('Could not export canvas');
    } finally {
      _transferActive = false;
    }
  }

  Future<void> _backupLibrary() async {
    if (_transferActive || _fileId == null) return;
    _transferActive = true;
    try {
      if (await _library.backup()) _showMessage('Library backed up');
    } on FormatException catch (error) {
      _showMessage(error.message);
    } on Object {
      _showMessage('Could not back up library');
    } finally {
      _transferActive = false;
    }
  }

  Future<bool> _importCanvas() async {
    if (_transferActive || _fileId == null) return false;
    _transferActive = true;
    final fileId = _fileId!;
    try {
      final project = await _library.readProject();
      if (project == null ||
          !await _confirmReplacement(
            title: 'Replace canvas?',
            message: 'Importing replaces “${_library.library.file(fileId).name}”.',
            action: 'Replace canvas',
          )) {
        return false;
      }
      if (!mounted) return false;
      await _replace(() => _library.replaceCanvas(fileId, project));
      _showMessage('Canvas imported');
      return true;
    } on Object {
      _showMessage('Could not import canvas');
      return false;
    } finally {
      _transferActive = false;
    }
  }

  Future<bool> _restoreLibrary() async {
    if (_transferActive || _fileId == null) return false;
    _transferActive = true;
    try {
      final archive = await _library.readArchive();
      if (archive == null) return false;
      final count = archive.library.files.where((file) => !file.isFolder).length;
      if (!await _confirmReplacement(
        title: 'Replace library?',
        message:
            'Restore $count ${count == 1 ? 'canvas' : 'canvases'}? This replaces all existing canvases and folders.',
        action: 'Replace library',
      )) {
        return false;
      }
      if (!mounted) return false;
      await _replace(() => _library.restore(archive));
      _showMessage('Library restored');
      return true;
    } on Object {
      _showMessage('Could not restore library');
      return false;
    } finally {
      _transferActive = false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Editor connection ----------

  @override
  Widget build(BuildContext context) {
    final fileId = _fileId;
    final token = _replacement.value.token;
    return CanvasPage(
      replacement: _replacement,
      blocked: _blocked,
      libraryPath: fileId == null
          ? const ['Untitled']
          : _library.library.path(_library.library.currentId).map((file) => file.name).toList(),
      attachmentStore: widget.attachmentStore,
      onDocumentChanged: (document) {
        if (fileId != null && identical(token, _replacement.value.token) && identical(token, _library.documentToken)) {
          _library.updateDocument(fileId, document);
        }
      },
      onOpenLibrary: _showLibrary,
      onImportCanvas: _importCanvas,
      onExportCanvas: _exportCanvas,
      onBackupLibrary: _backupLibrary,
      onRestoreLibrary: _restoreLibrary,
      readClipboard: widget.readClipboard,
      writeClipboardText: widget.writeClipboardText,
      themeMode: widget.themeMode,
      onSurfaceStyleChanged: widget.onSurfaceStyleChanged,
      onThemeModeChanged: widget.onThemeModeChanged,
    );
  }
}
