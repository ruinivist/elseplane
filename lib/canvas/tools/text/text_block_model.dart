// Owns editable text element state and persistence synchronization.
// Used by text rendering, editing, transformation, and document storage.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_clipboard.dart';
import 'package:elseplane/canvas/editor/canvas_element_model.dart';
import 'package:flutter/material.dart';
import 'package:scroll_animator/scroll_animator.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';

// ---------- Models ----------

/// Owns controllers and mutable state for a persisted text element.
/// Used by the text tool, Markdown surfaces, controls, and persistence.
class TextBlockModel extends RotatableCanvasElementModel<TextElementData> {
  // ---------- Construction ----------

  TextBlockModel(TextElementData data) : super(data) {
    controller = TextEditingController(text: data.markdown);
    controller.addListener(_syncMarkdown);
  }

  // ---------- State and geometry ----------

  TextElementData get node => data;
  late final TextEditingController controller;
  VoidCallback? onContentChanged;
  final FocusNode focusNode = FocusNode();
  final scrollController = AnimatedScrollController(
    animationFactory: const ChromiumEaseInOut(),
  );
  bool _editing = false;
  bool _disposed = false;
  bool get disposed => _disposed;

  @override
  double get rotation => node.rotation;

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize => Size(data.width, data.height ?? textNodeMinimumHeight);

  @override
  void moveBy(Offset delta) {
    if (delta == Offset.zero) return;
    replaceData(data.copyWith(position: data.position + delta));
  }

  bool get editing => _editing;

  set editing(bool value) {
    if (_editing == value) return;
    if (!value) invalidatePendingEdits();
    _editing = value;
    notifyListeners();
  }

  TextNodeStyle get style => node.style;

  set style(TextNodeStyle value) {
    if (_sameStyle(node.style, value)) return;
    replaceData(data.copyWith(style: value));
  }

  void resize(Size renderedSize, Offset delta) {
    final width = math.max(textNodeMinimumWidth, node.width + delta.dx);
    final height = math.max(
      textNodeMinimumHeight,
      (node.height ?? renderedSize.height) + delta.dy,
    );
    if (node.width == width && node.height == height) return;
    replaceData(data.copyWith(width: width, height: height));
  }

  @override
  void rotate(double angle) {
    if (node.rotation == angle) return;
    replaceData(data.copyWith(rotation: angle));
  }

  // ---------- Content insertion ----------

  Future<void> paste(Future<ClipboardReader> readerFuture, AttachmentStore store) async {
    final generation = asyncEditGeneration;
    try {
      final reader = await readerFuture;
      if (generation != asyncEditGeneration) return;
      final clipboard = await readCanvasClipboard(reader);
      if (generation != asyncEditGeneration) return;
      if (clipboard.image case final image?) {
        await insertPastedImage(image.bytes, image.extension, store);
      } else if (clipboard.text case final text?) {
        insertPastedText(text);
      }
    } on Object {
      if (generation != asyncEditGeneration) return;
      rethrow;
    }
  }

  Future<void> insertPastedImage(
    Uint8List bytes,
    String extension,
    AttachmentStore store,
  ) async {
    final generation = asyncEditGeneration;
    try {
      validateAttachmentSize(bytes.length, 'Image exceeds 10 MiB');
      final path = 'attachments/${const Uuid().v4()}.$extension';
      if (generation != asyncEditGeneration) return;
      var written = false;
      try {
        await store.write(path, bytes);
        written = true;
      } finally {
        if (!written || generation != asyncEditGeneration) {
          try {
            await store.delete(path);
          } on Object {
            // Cleanup cannot revive a canceled edit or hide the write failure.
          }
        }
      }
      if (generation != asyncEditGeneration) return;
      _insertText('![pasted image]($path)');
    } on Object {
      if (generation != asyncEditGeneration) return;
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
  void synchronizeRestoredData(TextElementData previous) {
    if (controller.text != data.markdown) controller.text = data.markdown;
  }

  void _syncMarkdown() {
    if (node.markdown == controller.text) return;
    replaceData(data.copyWith(markdown: controller.text), rebuild: false);
    onContentChanged?.call();
  }

  // ---------- Lifecycle ----------

  @override
  void dispose() {
    _disposed = true;
    onContentChanged = null;
    controller
      ..removeListener(_syncMarkdown)
      ..dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

// ---------- Helpers ----------

bool _sameStyle(TextNodeStyle first, TextNodeStyle second) {
  return first.fontFamily == second.fontFamily && first.color == second.color && first.background == second.background;
}
