// Owns media source resolution, sizing, activation, and persisted state.
// Used by the media tool, attachment storage, and canvas persistence flows.

part of 'media_tool.dart';

// ---------- Models ----------

/// Owns media loading state and synchronizes it with persisted element data.
/// Used by media rendering, editing, resizing, and attachment storage.
class MediaModel extends RotatableCanvasElementModel<MediaElementData> {
  // ---------- Construction ----------

  MediaModel(MediaElementData data, this.attachmentStore) : super(data) {
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

  // ---------- State and geometry ----------

  ImageProvider<Object>? get image => _image;

  bool get hasImage => _image != null && _aspectRatio != null;

  @override
  bool get canRotate => hasImage;

  @override
  double get rotation => data.rotation;

  double get urlPanelWidth => hasImage ? math.max(mediaUrlPanelMinimumWidth, data.width) : mediaUrlPanelMinimumWidth;

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize =>
      hasImage ? Size(data.width, data.width / _aspectRatio!) : Size(urlPanelWidth, _mediaUrlPanelCanvasHeight);

  @override
  void moveBy(Offset delta) {
    if (delta == Offset.zero) return;
    data.position += delta;
    notifyDocumentChanged();
  }

  void resizeBy(Offset delta) {
    final aspectRatio = _aspectRatio;
    if (aspectRatio == null) return;
    final inverseRatio = 1 / aspectRatio;
    final widthDelta = (delta.dx + delta.dy * inverseRatio) / (1 + inverseRatio * inverseRatio);
    final width = math.max(mediaNodeMinimumWidth, data.width + widthDelta);
    if (width == data.width) return;
    data.width = width;
    notifyDocumentChanged();
  }

  @override
  void rotate(double angle) {
    if (data.rotation == angle) return;
    data.rotation = angle;
    notifyDocumentChanged();
  }

  // ---------- Image updates ----------

  void commitUrl() {
    if (data.url == controller.text) return;
    data.url = controller.text;
    _loadImage();
    notifyDocumentChanged();
  }

  Future<void> paste(Future<ClipboardReader> readerFuture) async {
    final generation = asyncEditGeneration;
    try {
      final reader = await readerFuture;
      if (generation != asyncEditGeneration) return;
      final clipboard = await readCanvasClipboard(reader);
      if (generation != asyncEditGeneration) return;
      if (clipboard.image case final image?) {
        await setDeviceImage(image.bytes, image.extension);
      } else if (clipboard.text case final text?) {
        _insertPastedText(text);
        if (!focusNode.hasFocus) commitUrl();
      }
    } on Object {
      if (generation != asyncEditGeneration) return;
      rethrow;
    }
  }

  Future<void> setDeviceImage(Uint8List bytes, String extension) async {
    final generation = asyncEditGeneration;
    try {
      final normalizedExtension = extension.toLowerCase() == 'jpeg' ? 'jpg' : extension.toLowerCase();
      if (!const {'png', 'jpg', 'gif', 'webp'}.contains(normalizedExtension)) {
        throw const FormatException('Unsupported image type');
      }
      validateAttachmentSize(bytes.length, 'Image exceeds 10 MiB');

      final path = 'attachments/${const Uuid().v4()}.$normalizedExtension';
      final ratio = await _imageAspectRatio(bytes);
      if (generation != asyncEditGeneration) return;
      await attachmentStore.write(path, bytes);
      if (generation != asyncEditGeneration) {
        await attachmentStore.delete(path);
        return;
      }

      data.url = path;
      controller.text = path;
      _detachImage();
      _image = MemoryImage(bytes);
      _aspectRatio = ratio;
      notifyDocumentChanged();
    } on Object {
      if (generation != asyncEditGeneration) return;
      rethrow;
    }
  }

  // ---------- Private helpers ----------

  void _insertPastedText(String text) {
    final selection = controller.selection;
    controller.value = controller.value
        .replaced(selection, text)
        .copyWith(
          selection: TextSelection.collapsed(offset: selection.start + text.length),
          composing: TextRange.empty,
        );
  }

  @override
  void synchronizeRestoredData(MediaElementData previous) {
    if (controller.text != data.url) controller.text = data.url;
    if (previous.url.trim() != data.url.trim()) _loadImage();
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
  void dispose() {
    _detachImage();
    controller.dispose();
    focusNode
      ..removeListener(_commitOnFocusLost)
      ..dispose();
    super.dispose();
  }
}
