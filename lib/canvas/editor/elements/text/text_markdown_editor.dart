// Provides Markdown text entry and clipboard insertion for text blocks.
// Used by the text tool whenever a text element enters editing mode.

import 'dart:async';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/elements/text/text_editor_resources.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';

// ---------- Editor ----------

/// Renders the focused Markdown source editor and handles rich paste data.
/// Used by the text tool through the active [TextEditorResources].
class TextMarkdownEditor extends StatefulWidget {
  const TextMarkdownEditor({required this.model, required this.attachmentStore, this.onInteract, super.key});

  final TextEditorResources model;
  final AttachmentStore attachmentStore;
  final VoidCallback? onInteract;

  @override
  State<TextMarkdownEditor> createState() => _TextMarkdownEditorState();
}

class _TextMarkdownEditorState extends State<TextMarkdownEditor> {
  // ---------- State ----------

  ClipboardEvents? get _events => ClipboardEvents.instance;

  // ---------- Lifecycle ----------

  @override
  void initState() {
    super.initState();
    _events?.registerPasteEventListener(_onWebPaste);
  }

  @override
  void dispose() {
    _events?.unregisterPasteEventListener(_onWebPaste);
    super.dispose();
  }

  // ---------- Event handlers ----------

  void _onWebPaste(ClipboardReadEvent event) {
    if (!widget.model.focusNode.hasFocus) return;
    unawaited(_paste(event.getClipboardReader()));
  }

  Future<void> _paste(Future<ClipboardReader> readerFuture) async {
    try {
      await widget.model.paste(readerFuture, widget.attachmentStore);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not paste image')),
      );
    }
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final code = theme.typo.code;
    return Actions(
      actions: {
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (_) {
            final clipboard = SystemClipboard.instance;
            if (clipboard != null) unawaited(_paste(clipboard.read()));
            return null;
          },
        ),
      },
      child: TextField(
        key: const ValueKey('text-markdown-editor'),
        contextMenuBuilder: null,
        onTap: widget.onInteract,
        onTapAlwaysCalled: true,
        controller: widget.model.controller,
        focusNode: widget.model.focusNode,
        scrollController: widget.model.scrollController,
        expands: widget.model.node.height != null,
        maxLines: null,
        cursorColor: colors.accent,
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(24),
          hintText: 'Type something...',
          hintStyle: theme.typo.body.copyWith(color: colors.textMuted),
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
        style: code.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

// ---------- Clipboard edits ----------

extension TextClipboardEdits on TextEditorResources {
  Future<void> paste(Future<ClipboardReader> readerFuture, AttachmentStore store) async {
    final token = session.captureEdit(data.id);
    try {
      final reader = await readerFuture;
      if (!token.isCurrent || !attached) return;
      final clipboard = await readCanvasClipboard(reader);
      if (!token.isCurrent || !attached) return;
      if (clipboard.image case final image?) {
        await insertPastedImage(image.bytes, image.extension, store);
      } else if (clipboard.text case final text?) {
        insertPastedText(text);
      }
    } on Object {
      if (!token.isCurrent || !attached) return;
      rethrow;
    }
  }

  Future<void> insertPastedImage(
    Uint8List bytes,
    String extension,
    AttachmentStore store,
  ) async {
    final token = session.captureEdit(data.id);
    try {
      final path = 'attachments/${const Uuid().v4()}.$extension';
      await validateCanvasAttachment(path, bytes);
      if (!token.isCurrent || !attached) return;
      var written = false;
      try {
        await store.write(path, bytes);
        written = true;
      } finally {
        if (!written || !token.isCurrent || !attached) {
          try {
            await store.delete(path);
          } on Object {
            // Cleanup cannot revive a canceled edit or hide the write failure.
          }
        }
      }
      if (!token.isCurrent || !attached) return;
      insertPastedText('![pasted image]($path)');
    } on Object {
      if (!token.isCurrent || !attached) return;
      rethrow;
    }
  }
}
