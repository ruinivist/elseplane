// Retains text controllers and requests accepted content edits.
// Used by text views, clipboard insertion, and editing controls.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:flutter/material.dart';
import 'package:scroll_animator/scroll_animator.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';

// ---------- Models ----------

/// Owns controllers and mutable state for a persisted text element.
/// Used by the text tool, Markdown surfaces, controls, and persistence.
class TextBlockModel extends RotatableCanvasElementModel<TextElementData> {
  // ---------- Construction ----------

  TextBlockModel(EditorSession session, TextElementData data) : super(session, data) {
    controller = TextEditingController(text: data.markdown);
    controller.addListener(_syncMarkdown);
  }

  // ---------- State and geometry ----------

  TextElementData get node => data;
  late final TextEditingController controller;
  final FocusNode focusNode = FocusNode();
  final scrollController = AnimatedScrollController(
    animationFactory: const ChromiumEaseInOut(),
  );

  @override
  double get rotation => node.rotation;

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize => Size(data.width, data.height ?? textNodeMinimumHeight);

  bool get editing => attached && session.editing == (id: data.id, field: EditorField.markdown);
  TextNodeStyle get style => node.style;

  // ---------- Content insertion ----------

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
      validateAttachmentSize(bytes.length, 'Image exceeds 10 MiB');
      final path = 'attachments/${const Uuid().v4()}.$extension';
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
      _insertText('![pasted image]($path)');
    } on Object {
      if (!token.isCurrent || !attached) return;
      rethrow;
    }
  }

  void insertPastedText(String text) => _insertText(text);

  // ---------- Private helpers ----------

  void _insertText(String text) {
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    final from = math.min(start, end).clamp(0, controller.text.length);
    final to = math.max(start, end).clamp(0, controller.text.length);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(from, to, text),
      selection: TextSelection.collapsed(offset: from + text.length),
    );
  }

  @override
  void synchronizeData(TextElementData previous, {required bool restored}) {
    if (controller.text != data.markdown) controller.text = data.markdown;
  }

  void _syncMarkdown() {
    if (!attached || node.markdown == controller.text) return;
    session.setMarkdown(data.id, controller.text);
  }

  // ---------- Lifecycle ----------

  @override
  void dispose() {
    controller
      ..removeListener(_syncMarkdown)
      ..dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
