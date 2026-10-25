// Retains media drafts, image resources, and import work.
// Used by media views while the session owns saved source and geometry.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/canvas/editor/media_source.dart';
import 'package:flutter/material.dart';

// ---------- Resources ----------

/// Owns media loading state and synchronizes it with persisted element data.
/// Used by media rendering, editing, resizing, and attachment storage.
class MediaResources extends ElementResources<MediaElementData> {
  // ---------- Construction ----------

  MediaResources(EditorSession session, MediaElementData data, this.attachmentStore) : super(session, data) {
    controller = TextEditingController(text: data.url);
    focusNode.addListener(_commitOnFocusLost);
    _loadImage();
  }

  final AttachmentStore attachmentStore;
  late final TextEditingController controller;
  final focusNode = FocusNode();
  ImageProvider<Object>? _image;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Object? _attachmentLoad;
  double? _aspectRatio;
  bool _applyingDeviceImage = false;

  // ---------- State and geometry ----------

  ImageProvider<Object>? get image => _image;

  bool get hasImage => _image != null && _aspectRatio != null;

  bool get canRotate => hasImage;

  double get rotation => data.rotation;

  double get urlPanelWidth => hasImage ? math.max(mediaUrlPanelMinimumWidth, data.width) : mediaUrlPanelMinimumWidth;

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize =>
      hasImage ? Size(data.width, data.width / _aspectRatio!) : Size(urlPanelWidth, mediaUrlPanelCanvasHeight);

  double? get aspectRatio => _aspectRatio;

  // ---------- Image updates ----------

  void commitUrl() {
    if (!attached || data.url == controller.text) return;
    session.setMediaUrl(data.id, controller.text);
  }

  void applyDeviceImage(Uint8List bytes, double ratio, String path) {
    _detachImage();
    _image = MemoryImage(bytes);
    _aspectRatio = ratio;
    _applyingDeviceImage = true;
    try {
      session.setMediaUrl(data.id, path);
    } finally {
      _applyingDeviceImage = false;
    }
  }

  // ---------- Private helpers ----------

  void insertPastedText(String text) {
    final selection = controller.selection;
    controller.value = controller.value
        .replaced(selection, text)
        .copyWith(
          selection: TextSelection.collapsed(offset: selection.start + text.length),
          composing: TextRange.empty,
        );
  }

  @override
  void synchronizeData(MediaElementData previous, {required bool restored}) {
    if ((restored || previous.url != data.url) && controller.text != data.url) controller.text = data.url;
    if (!_applyingDeviceImage && previous.url.trim() != data.url.trim()) _loadImage();
  }

  void _commitOnFocusLost() {
    if (!focusNode.hasFocus) commitUrl();
  }

  void _loadImage() {
    _detachImage();
    final source = data.url.trim();
    if (attachmentPathPattern.hasMatch(source)) {
      final load = Object();
      _attachmentLoad = load;
      unawaited(_loadAttachment(source, load));
      return;
    }
    if (!isSupportedMediaUrl(source)) return;

    _attachImage(NetworkImage(source));
  }

  Future<void> _loadAttachment(String path, Object load) async {
    try {
      final bytes = await attachmentStore.read(path);
      if (_attachmentLoad != load) return;
      _attachImage(MemoryImage(bytes));
    } on Object {
      if (_attachmentLoad != load) return;
      notifyListeners();
    }
  }

  void _attachImage(ImageProvider<Object> image) {
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        final ratio = info.image.width / info.image.height;
        if (_aspectRatio == ratio && _image == image) return;
        _image = image;
        _aspectRatio = ratio;
        notifyListeners();
      },
      onError: (_, _) {
        _image = null;
        _aspectRatio = null;
        notifyListeners();
      },
    );
    _image = image;
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _detachImage() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
    _attachmentLoad = null;
    _image = null;
    _aspectRatio = null;
  }

  // ---------- Lifecycle ----------

  @override
  void detach() {
    _detachImage();
    super.detach();
  }

  @override
  void dispose() {
    _detachImage();
    controller.dispose();
    focusNode
      ..removeListener(_commitOnFocusLost)
      ..dispose();
    super.dispose();
  }
}
