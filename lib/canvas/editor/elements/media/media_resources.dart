// Retains media drafts, image resources, and import work.
// Used by media views while the session owns saved source and geometry.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/canvas/editor/elements/media/media_link_preview.dart';
import 'package:elseplane/canvas/editor/media_source.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ---------- Resources ----------

/// Owns media loading state and synchronizes it with persisted element data.
/// Used by media rendering, editing, resizing, and attachment storage.
class MediaResources extends ElementResources<MediaElementData> {
  // ---------- Construction ----------

  MediaResources(
    EditorSession session,
    MediaElementData data,
    this.attachmentStore, {
    http.Client? previewClient,
  }) : _injectedPreviewClient = previewClient,
       super(session, data) {
    controller = TextEditingController(text: data.url);
    focusNode.addListener(_commitOnFocusLost);
    _loadImage();
  }

  final AttachmentStore attachmentStore;
  final http.Client? _injectedPreviewClient;
  http.Client? _ownedPreviewClient;
  late final TextEditingController controller;
  final focusNode = FocusNode();
  final cardFocusNode = FocusNode(debugLabel: 'Media link card');
  ImageProvider<Object>? _image;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  double? _aspectRatio;
  bool _applyingDeviceImage = false;
  Object? _imageIdentity;
  Object _previewIdentity = Object();
  bool _previewStarted = false;
  bool _previewFailed = false;
  MediaLinkMetadata? _linkMetadata;
  ImageProvider<Object>? _thumbnailImage;
  ImageStream? _thumbnailStream;
  ImageStreamListener? _thumbnailListener;
  bool _thumbnailFailed = false;

  // ---------- State and geometry ----------

  ImageProvider<Object>? get image => _image;

  bool get hasImage => _image != null && _aspectRatio != null;

  bool get isLink => isLinkMediaSource(data.url);

  bool get canRotate => isLink || hasImage;

  MediaLinkTarget? get linkTarget => isLink ? recognizeMediaLink(data.url) : null;

  MediaLinkMetadata? get linkMetadata => _linkMetadata;

  ImageProvider<Object>? get thumbnailImage => _thumbnailImage;

  bool get thumbnailFailed => _thumbnailFailed;

  bool get linkPreviewFailed => _previewFailed;

  http.Client get _previewClient => _injectedPreviewClient ?? (_ownedPreviewClient ??= http.Client());

  double get rotation => data.rotation;

  double get urlPanelWidth =>
      hasImage || isLink ? math.max(mediaUrlPanelMinimumWidth, data.width) : mediaUrlPanelMinimumWidth;

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize => isLink
      ? mediaLinkCardSize(data.url, data.width)
      : hasImage
      ? Size(data.width, data.width / _aspectRatio!)
      : Size(urlPanelWidth, mediaUrlPanelCanvasHeight);

  double? get aspectRatio => isLink ? canvasSize.width / canvasSize.height : _aspectRatio;

  // ---------- Image updates ----------

  void commitUrl() {
    if (!attached) return;
    final url = controller.text;
    if (data.url != url) session.setMediaUrl(data.id, url);
  }

  /// Starts one metadata request for a mounted card and retains its result across culling.
  void loadLinkPreview() {
    final target = linkTarget;
    if (target == null || !attached || _previewStarted) return;
    _previewStarted = true;
    final identity = _previewIdentity;
    unawaited(_fetchLinkPreview(target, identity));
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
    if (previous.url != data.url) {
      _resetLinkPreview();
      if (!_applyingDeviceImage) _loadImage();
    }
  }

  void _commitOnFocusLost() {
    if (!focusNode.hasFocus) commitUrl();
  }

  void _loadImage() {
    _detachImage();
    final source = data.url;
    if (!isImageMediaSource(source)) return;
    final identity = Object();
    _imageIdentity = identity;
    if (attachmentPathPattern.hasMatch(source)) {
      unawaited(_loadAttachment(source, identity));
      return;
    }
    final uri = resolveMediaUri(source);
    if (uri != null) _attachImage(NetworkImage(uri.toString()), identity);
  }

  Future<void> _loadAttachment(String path, Object load) async {
    try {
      final bytes = await attachmentStore.read(path);
      if (!identical(_imageIdentity, load) || !attached) return;
      _attachImage(MemoryImage(bytes), load);
    } on Object {
      if (!identical(_imageIdentity, load) || !attached) return;
      notifyListeners();
    }
  }

  void _attachImage(ImageProvider<Object> image, Object identity) {
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        if (!identical(_imageIdentity, identity) || !attached) return;
        final ratio = info.image.width / info.image.height;
        if (_aspectRatio == ratio && _image == image) return;
        _image = image;
        _aspectRatio = ratio;
        notifyListeners();
      },
      onError: (_, _) {
        if (!identical(_imageIdentity, identity) || !attached) return;
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

  Future<void> _fetchLinkPreview(MediaLinkTarget target, Object identity) async {
    MediaLinkMetadata? metadata;
    try {
      metadata = await MediaLinkPreviewLoader(_previewClient).load(target);
    } on Object {
      metadata = null;
    }
    if (!_isCurrentPreview(identity)) return;
    _linkMetadata = metadata;
    _previewFailed = metadata == null;
    if (metadata?.thumbnailUri case final uri?) _attachThumbnail(uri, identity);
    notifyListeners();
  }

  bool _isCurrentPreview(Object identity) => attached && identical(_previewIdentity, identity) && isLink;

  void _attachThumbnail(Uri uri, Object identity) {
    final image = NetworkImage(uri.toString());
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
      },
      onError: (_, _) {
        if (!_isCurrentPreview(identity)) return;
        _thumbnailFailed = true;
        notifyListeners();
      },
    );
    _thumbnailImage = image;
    _thumbnailStream = stream;
    _thumbnailListener = listener;
    stream.addListener(listener);
  }

  void _resetLinkPreview() {
    _previewIdentity = Object();
    _previewStarted = false;
    _previewFailed = false;
    _linkMetadata = null;
    _thumbnailFailed = false;
    final stream = _thumbnailStream;
    final listener = _thumbnailListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _thumbnailStream = null;
    _thumbnailListener = null;
    _thumbnailImage = null;
  }

  void _detachImage() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
    _imageIdentity = null;
    _image = null;
    _aspectRatio = null;
  }

  // ---------- Lifecycle ----------

  @override
  void detach() {
    _detachImage();
    _resetLinkPreview();
    super.detach();
  }

  @override
  void dispose() {
    _detachImage();
    _resetLinkPreview();
    controller.dispose();
    focusNode
      ..removeListener(_commitOnFocusLost)
      ..dispose();
    cardFocusNode.dispose();
    _ownedPreviewClient?.close();
    super.dispose();
  }
}
