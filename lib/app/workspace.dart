// Connects the canvas editor lifetime to library durability and file presentation.
// Used by the root app to compose injected storage, editor snapshots, and settings actions.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_page.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/github/github_api.dart';
import 'package:elseplane/github/github_workspace_panel.dart';
import 'package:elseplane/library/library_controller.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/transfer/canvas_project_files.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/library/widgets/canvas_file_picker.dart';
import 'package:elseplane/theme/preset_colors.dart';
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
    this.githubApi,
    this.navigateGitHubAuthorization,
    this.consumeGitHubCompletion,
    this.openGitHubLink,
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
  final GitHubApi? githubApi;
  final void Function(Uri)? navigateGitHubAuthorization;
  final bool Function()? consumeGitHubCompletion;
  final void Function(String url)? openGitHubLink;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  // ---------- Lifetime ----------

  late final _library = LibraryController(
    store: widget.libraryStore,
    attachments: widget.attachmentStore,
    files: widget.projectFiles,
    onAttachmentPathsChanged: _invalidateAttachments,
  );
  EditorSession? _editor;
  VoidCallback? _documentListener;
  String? _fileId;
  Object? _reportedSaveError;
  var _blocked = false;
  var _transferActive = false;
  void Function(Set<String>)? _attachmentInvalidator;

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

  bool _beginTransfer() {
    if (_transferActive || _blocked || _editor == null) return false;
    setState(() {
      _transferActive = true;
      _blocked = true;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    return true;
  }

  void _endTransfer() {
    if (!mounted) return;
    setState(() {
      _transferActive = false;
      _blocked = false;
    });
  }

  void _libraryChanged() {
    if (!mounted) return;
    final error = _library.saveError;
    if (error != null && !identical(error, _reportedSaveError)) _showMessage('Could not save canvas');
    _reportedSaveError = error;
    setState(() {});
  }

  void _invalidateAttachments(Set<String> paths) => _attachmentInvalidator?.call(paths);

  // Keep a stable callback tear-off so CanvasView does not re-register on every rebuild.
  // ignore: use_setters_to_change_properties
  void _registerAttachmentInvalidator(void Function(Set<String>)? invalidator) => _attachmentInvalidator = invalidator;

  void _replaceEditor() => setState(() {
    final previous = _editor;
    if (_documentListener != null) previous?.documentChanges.removeListener(_documentListener!);
    previous?.endLifetime();
    final fileId = _fileId = _library.library.currentId;
    final token = _library.documentToken;
    final editor = _editor = EditorSession(
      _library.library.current.document!,
      initialColor: defaultCanvasColor,
      defaults: previous?.defaults,
    );
    _documentListener = () {
      if (editor.isLive && identical(token, _library.documentToken)) _library.updateDocument(fileId, editor.document);
    };
    editor.documentChanges.addListener(_documentListener!);
    if (previous != null) WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  });

  @override
  void dispose() {
    if (_documentListener != null) _editor?.documentChanges.removeListener(_documentListener!);
    _editor?.dispose();
    _library
      ..removeListener(_libraryChanged)
      ..dispose();
    super.dispose();
  }

  // ---------- File presentation ----------

  Future<void> _showLibrary() async {
    if (_editor == null || _transferActive || _blocked) return;
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

  // ---------- Settings transfers ----------

  Future<void> _exportCanvas() async {
    if (_fileId == null || !_beginTransfer()) return;
    try {
      await _library.flush();
      if (await _library.exportCanvas(_fileId!)) _showMessage('Canvas exported');
    } on Object {
      _showMessage('Could not export canvas');
    } finally {
      _endTransfer();
    }
  }

  Future<void> _exportLibrary() async {
    if (_fileId == null || !_beginTransfer()) return;
    try {
      await _library.flush();
      if (await _library.exportLibrary()) _showMessage('Library exported');
    } on Object {
      _showMessage('Could not export library');
    } finally {
      _endTransfer();
    }
  }

  Future<bool> _import() async {
    if (_fileId == null || !_beginTransfer()) return false;
    try {
      final source = await _library.readTransferSource();
      if (!mounted || source == null) return false;
      final result = await _importTransfer(source);
      return result.failure == null && result.metadataSaved;
    } on FormatException {
      await _showTransferReport(
        TransferImportResult(
          skippedCanvases: const [],
          writtenImagePaths: const [],
          metadataSaved: false,
          failure: const TransferFailure(reason: 'Could not prepare transfer', stage: TransferFailureStage.preparation),
        ),
      );
      return false;
    } on Exception {
      await _showTransferReport(
        TransferImportResult(
          skippedCanvases: const [],
          writtenImagePaths: const [],
          metadataSaved: false,
          failure: const TransferFailure(reason: 'Could not prepare transfer', stage: TransferFailureStage.preparation),
        ),
      );
      return false;
    } finally {
      _endTransfer();
    }
  }

  Future<TransferImportResult> _importTransfer(TransferSource source) async {
    TransferImport? candidate;
    try {
      await _library.flush();
      candidate = await decodeTransfer(source);
      final merge = await _library.previewTransferImport(candidate);
      if (!mounted) {
        return _transferResult(candidate.skippedCanvases);
      }
      if (merge.overwritePaths.isNotEmpty && !await _confirmTransferOverwrite(merge.overwritePaths)) {
        final result = _transferResult(candidate.skippedCanvases);
        await _showTransferReport(result, cancelled: true);
        return result;
      }
      if (!mounted) return _transferResult(candidate.skippedCanvases);

      final token = _library.documentToken;
      final result = await _library.importTransfer(merge, confirmedOverwritePaths: merge.overwritePaths);
      final affected = <String>{
        ...result.writtenImagePaths,
        if (result.failure?.stage == TransferFailureStage.imageWrite) result.failure!.path!,
      };
      if (affected.isNotEmpty) _invalidateAttachments(affected);
      if (result.metadataSaved && !identical(token, _library.documentToken) && mounted) _replaceEditor();
      await _showTransferReport(result, candidate: candidate);
      return result;
    } on FormatException {
      final result = _transferResult(
        candidate?.skippedCanvases ?? const [],
        failure: const TransferFailure(reason: 'Could not prepare transfer', stage: TransferFailureStage.preparation),
      );
      await _showTransferReport(result);
      return result;
    } on GitHubApiException catch (error) {
      final result = _transferResult(
        candidate?.skippedCanvases ?? const [],
        failure: TransferFailure(reason: error.message, stage: TransferFailureStage.preparation),
      );
      await _showTransferReport(result);
      return result;
    } on Exception {
      final result = _transferResult(
        candidate?.skippedCanvases ?? const [],
        failure: const TransferFailure(reason: 'Could not prepare transfer', stage: TransferFailureStage.preparation),
      );
      await _showTransferReport(result);
      return result;
    }
  }

  TransferImportResult _transferResult(
    List<TransferIssue> skipped, {
    TransferFailure? failure,
  }) => TransferImportResult(
    skippedCanvases: skipped,
    writtenImagePaths: const [],
    metadataSaved: false,
    failure: failure,
  );

  Future<bool> _confirmTransferOverwrite(Set<String> paths) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => SurfaceConfirmationDialog(
            title: const Text('Overwrite canvases?'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The following canvas paths already exist. Shared images may also change in other canvases.',
                ),
                const SizedBox(height: 12),
                for (final path in paths.toList()..sort()) Text(path),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Overwrite and import')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showTransferReport(
    TransferImportResult result, {
    TransferImport? candidate,
    bool cancelled = false,
  }) async {
    if (!mounted) return;
    final lines = <String>[
      if (cancelled) 'Import canceled.',
      if (!cancelled && result.metadataSaved)
        'Imported ${candidate?.canvases.length ?? 0} ${candidate?.canvases.length == 1 ? 'canvas' : 'canvases'}.',
      if (!cancelled && !result.metadataSaved && result.writtenImagePaths.isNotEmpty && result.failure == null)
        'Images changed; the library metadata was unchanged.',
      if (result.failure case final failure?) ...[
        if (failure.stage == TransferFailureStage.imageWrite ||
            (failure.stage == TransferFailureStage.publication && result.writtenImagePaths.isNotEmpty))
          'Images may have changed; imported canvases were not saved.',
        '${failure.reason}${failure.path == null ? '' : ': ${failure.path}'}',
      ],
      if (result.skippedCanvases.isNotEmpty) 'Skipped canvases:',
      for (final issue in result.skippedCanvases) '${issue.path}: ${issue.reason}',
      if (!cancelled && result.failure == null && !result.metadataSaved && result.writtenImagePaths.isEmpty)
        'No changes to import.',
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => SurfaceConfirmationDialog(
        title: const Text('Import result'),
        content: Text(lines.join('\n')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Editor connection ----------

  @override
  Widget build(BuildContext context) {
    final fileId = _fileId;
    final fileExists = fileId != null && _library.library.files.any((file) => file.id == fileId);
    return CanvasPage(
      session: _editor,
      blocked: _blocked,
      libraryPath: fileId == null
          ? const ['Untitled']
          : _library.library.path(_library.library.currentId).map((file) => file.name).toList(),
      attachmentStore: widget.attachmentStore,
      onOpenLibrary: _showLibrary,
      onImport: _import,
      onExportCanvas: _exportCanvas,
      onExportLibrary: _exportLibrary,
      canvasDirectory: fileExists ? _library.library.parentDirectory(fileId) : '',
      onAttachmentInvalidatorChanged: _registerAttachmentInvalidator,
      readClipboard: widget.readClipboard,
      writeClipboardText: widget.writeClipboardText,
      themeMode: widget.themeMode,
      onSurfaceStyleChanged: widget.onSurfaceStyleChanged,
      onThemeModeChanged: widget.onThemeModeChanged,
      bottomLeftPanelBuilder: widget.githubApi == null || _editor == null
          ? null
          : (finishInteraction) => GitHubWorkspacePanel(
              api: widget.githubApi!,
              library: _library,
              attachmentStore: widget.attachmentStore,
              currentFileId: fileId!,
              blocked: _blocked || _transferActive,
              beginTransfer: _beginTransfer,
              endTransfer: _endTransfer,
              onImportTransfer: _importTransfer,
              finishInteraction: finishInteraction,
              navigateGitHubAuthorization: widget.navigateGitHubAuthorization,
              consumeGitHubCompletion: widget.consumeGitHubCompletion,
              openGitHubLink: widget.openGitHubLink,
            ),
    );
  }
}
