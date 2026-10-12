// Owns code editor state, geometry, language, and data synchronization.
// Used by the code tool renderer and canvas persistence flow.

part of 'code_tool.dart';

// ---------- Models ----------

/// Owns code editor controllers and keeps them synchronized with element data.
/// Used by code block rendering and canvas persistence.
class CodeBlockModel extends RotatableCanvasElementModel<CodeElementData> {
  // ---------- Construction ----------

  CodeBlockModel(CodeElementData data) : super(data) {
    controller.text = data.source;
    controller.addListener(_syncSource);
    titleController = TextEditingController(text: data.title)..addListener(_syncTitle);
  }

  final controller = CodeLineEditingController(
    options: const CodeLineOptions(indentSize: 4),
  );
  late final TextEditingController titleController;
  VoidCallback? onContentChanged;
  final focusNode = FocusNode();
  final scrollController = CodeScrollController(
    verticalScroller: AnimatedScrollController(
      animationFactory: const ChromiumEaseInOut(),
    ),
    horizontalScroller: AnimatedScrollController(
      animationFactory: const ChromiumEaseInOut(),
    ),
  );

  @override
  set active(bool value) {
    if (active && !value) controller.cancelSelection();
    super.active = value;
  }

  // ---------- Geometry and language ----------

  @override
  Offset get canvasPosition {
    // The title extends above the body without moving its rotation center.
    const halfTitle = _codeTitleHeight / 2;
    return data.position +
        Offset(
          math.sin(rotation) * halfTitle,
          -halfTitle - math.cos(rotation) * halfTitle,
        );
  }

  @override
  Size get canvasSize => Size(size.width, size.height + _codeTitleHeight);

  Size get size => data.size;

  set size(Size value) {
    final nextSize = _clampSize(value);
    if (data.size == nextSize) return;
    data.size = nextSize;
    notifyDocumentChanged();
  }

  @override
  double get rotation => data.rotation;

  @override
  void rotate(double angle) {
    if (data.rotation == angle) return;
    data.rotation = angle;
    notifyDocumentChanged();
  }

  CodeLanguage get language => data.language;

  set language(CodeLanguage value) {
    if (data.language == value) return;
    data.language = value;
    notifyDocumentChanged();
  }

  String get title => data.title;

  set title(String value) {
    if (data.title == value) return;
    data.title = value;
    if (titleController.text != value) titleController.text = value;
    notifyDocumentChanged();
    onContentChanged?.call();
  }

  BlockBackgroundKind get background => data.background;

  set background(BlockBackgroundKind value) {
    if (data.background == value) return;
    data.background = value;
    notifyDocumentChanged();
  }

  bool get showLineNumbers => data.showLineNumbers;

  set showLineNumbers(bool value) {
    if (data.showLineNumbers == value) return;
    data.showLineNumbers = value;
    notifyDocumentChanged();
  }

  @override
  void moveBy(Offset delta) {
    if (delta == Offset.zero) return;
    data.position += delta;
    notifyDocumentChanged();
  }

  // ---------- Synchronization ----------

  @override
  void synchronizeRestoredData(CodeElementData previous) {
    if (controller.text != data.source) {
      controller.text = data.source;
      controller.clearHistory();
    }
    if (titleController.text != data.title) titleController.text = data.title;
  }

  void _syncTitle() => title = titleController.text;

  void _syncSource() {
    if (data.source == controller.text) return;
    data.source = controller.text;
    notifyDocumentChanged(rebuild: false);
    onContentChanged?.call();
  }

  // ---------- Lifecycle ----------

  @override
  void dispose() {
    onContentChanged = null;
    controller
      ..removeListener(_syncSource)
      ..dispose();
    titleController
      ..removeListener(_syncTitle)
      ..dispose();
    focusNode.dispose();
    scrollController
      ..verticalScroller.dispose()
      ..horizontalScroller.dispose()
      ..dispose();
    super.dispose();
  }
}

// ---------- Geometry ----------

Size _clampSize(Size size) {
  return Size(
    math.max(codeBlockMinimumSize.width, size.width),
    math.max(codeBlockMinimumSize.height, size.height),
  );
}
