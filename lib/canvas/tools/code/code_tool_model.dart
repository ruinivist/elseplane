// Retains code controllers and synchronizes accepted editor snapshots.
// Used by code views, clipboard insertion, and editing controls.

part of 'code_tool.dart';

// ---------- Models ----------

/// Owns code editor controllers and keeps them synchronized with element data.
/// Used by code block rendering and canvas persistence.
class CodeBlockModel extends RotatableCanvasElementModel<CodeElementData> {
  // ---------- Construction ----------

  CodeBlockModel(EditorSession session, CodeElementData data) : super(session, data) {
    controller.text = data.source;
    controller.addListener(_syncSource);
    titleController = TextEditingController(text: data.title)..addListener(_syncTitle);
  }

  final controller = CodeLineEditingController(options: const CodeLineOptions(indentSize: 4));
  late final TextEditingController titleController;
  final focusNode = FocusNode();
  final titleFocusNode = FocusNode();
  final scrollController = CodeScrollController(
    verticalScroller: AnimatedScrollController(
      animationFactory: const ChromiumEaseInOut(),
    ),
    horizontalScroller: AnimatedScrollController(
      animationFactory: const ChromiumEaseInOut(),
    ),
  );

  // ---------- Geometry and language ----------

  @override
  Offset get canvasPosition {
    // The title extends above the body without moving its rotation center.
    const halfTitle = codeTitleHeight / 2;
    return data.position +
        Offset(
          math.sin(rotation) * halfTitle,
          -halfTitle - math.cos(rotation) * halfTitle,
        );
  }

  @override
  Size get canvasSize => Size(size.width, size.height + codeTitleHeight);

  Size get size => data.size;

  @override
  double get rotation => data.rotation;
  CodeLanguage get language => data.language;
  String get title => data.title;
  BlockBackgroundKind get background => data.background;
  bool get showLineNumbers => data.showLineNumbers;

  Future<void> paste({bool intoTitle = false}) async {
    final token = session.captureEdit(data.id);
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!token.isCurrent || !attached) return;
      final text = clipboard?.text;
      if (text == null || text.isEmpty) return;
      if (intoTitle) {
        final value = titleController.value;
        final selection = value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
        titleController.value = FilteringTextInputFormatter.singleLineFormatter.formatEditUpdate(
          value,
          value
              .replaced(selection, text)
              .copyWith(
                selection: TextSelection.collapsed(offset: selection.start + text.length),
              ),
        );
      } else {
        controller.replaceSelection(text);
      }
    } on Object {
      if (!token.isCurrent || !attached) return;
      rethrow;
    }
  }

  // ---------- Synchronization ----------

  @override
  void synchronizeData(CodeElementData previous, {required bool restored}) {
    if (!active) controller.cancelSelection();
    if (controller.text != data.source) {
      controller.text = data.source;
      controller.clearHistory();
    }
    if (titleController.text != data.title) titleController.text = data.title;
  }

  void _syncTitle() {
    if (attached) session.setCodeTitle(data.id, titleController.text);
  }

  void _syncSource() {
    if (!attached || data.source == controller.text) return;
    session.setCodeSource(data.id, controller.text);
  }

  // ---------- Lifecycle ----------

  @override
  void dispose() {
    controller
      ..removeListener(_syncSource)
      ..dispose();
    titleController
      ..removeListener(_syncTitle)
      ..dispose();
    focusNode.dispose();
    titleFocusNode.dispose();
    scrollController
      ..verticalScroller.dispose()
      ..horizontalScroller.dispose()
      ..dispose();
    super.dispose();
  }
}
