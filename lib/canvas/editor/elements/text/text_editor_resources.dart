// Retains text controllers and requests accepted content edits.
// Used by text views, clipboard insertion, and editing controls.

import 'dart:math' as math;

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/canvas/editor/elements/text/text_markdown_images.dart';
import 'package:elseplane/ui/common/retained_scroll_controller.dart';
import 'package:flutter/material.dart';

// ---------- Resources ----------

/// Owns controllers and mutable state for a persisted text element.
/// Used by the text tool, Markdown surfaces, controls, and persistence.
class TextEditorResources extends ElementResources<TextElementData> {
  // ---------- Construction ----------

  TextEditorResources(EditorSession session, TextElementData data, AttachmentStore attachmentStore)
    : super(session, data) {
    images = TextMarkdownImages(data.markdown, attachmentStore);
    controller = TextEditingController(text: data.markdown);
    controller.addListener(_syncMarkdown);
  }

  // ---------- State and geometry ----------

  TextElementData get node => data;
  late final TextEditingController controller;
  late final TextMarkdownImages images;
  final FocusNode focusNode = FocusNode();
  final scrollController = RetainedScrollController();

  double get rotation => node.rotation;

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize => Size(data.width, data.height ?? textNodeMinimumHeight);

  bool get editing => attached && session.editing == (id: data.id, field: EditorField.markdown);
  TextNodeStyle get style => node.style;

  // ---------- Content insertion ----------

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
    if (previous.markdown != data.markdown) images.synchronize(data.markdown);
    if (controller.text != data.markdown) controller.text = data.markdown;
  }

  void _syncMarkdown() {
    if (!attached || node.markdown == controller.text) return;
    session.setMarkdown(data.id, controller.text);
  }

  // ---------- Lifecycle ----------

  @override
  void detach() {
    images.retire();
    super.detach();
  }

  @override
  void dispose() {
    controller
      ..removeListener(_syncMarkdown)
      ..dispose();
    focusNode.dispose();
    scrollController.dispose();
    images.dispose();
    super.dispose();
  }
}
