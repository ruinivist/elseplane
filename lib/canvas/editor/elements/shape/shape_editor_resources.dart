// Retains native text editing state for a persisted shape label.
// Owned by CanvasView across lazy culling.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/ui/common/retained_scroll_controller.dart';
import 'package:flutter/widgets.dart';

// ---------- Resources ----------

class ShapeEditorResources extends ElementResources<ShapeElementData> {
  ShapeEditorResources(EditorSession session, ShapeElementData data) : super(session, data) {
    controller = TextEditingController(text: data.text)..addListener(_syncText);
  }

  late final TextEditingController controller;
  final FocusNode focusNode = FocusNode();
  final RetainedScrollController scrollController = RetainedScrollController();

  bool get editing => attached && session.editing == (id: data.id, field: EditorField.shapeText);

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize => data.size;

  void enterEditing() {
    if (!attached) return;
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    session.editField((id: data.id, field: EditorField.shapeText));
  }

  void finishEditing() {
    if (!attached) return;
    if (session.editing == (id: data.id, field: EditorField.shapeText)) session.editField(null);
    focusNode.unfocus();
  }

  @override
  void synchronizeData(ShapeElementData previous, {required bool restored}) {
    if (controller.text == data.text) return;
    controller.value = TextEditingValue(
      text: data.text,
      selection: TextSelection.collapsed(offset: data.text.length),
    );
  }

  void _syncText() {
    if (!attached || data.text == controller.text) return;
    session.setShapeText(data.id, controller.text);
  }

  @override
  void dispose() {
    controller
      ..removeListener(_syncText)
      ..dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
