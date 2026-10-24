// Projects saved shape values into canvas geometry.
// Used by shape views while the session owns edits and interaction state.

part of 'shape_tool.dart';

// ---------- Models ----------

/// Adapts persisted shape data to selectable and resizable canvas geometry.
/// Used by the canvas selection and shape rendering flows.
class ShapeModel extends CanvasElementModel<ShapeElementData> {
  ShapeModel(super.session, super.data);

  ShapeKind get kind => data.kind;
  Color get strokeColor => data.strokeColor;
  Color? get fillColor => data.fillColor;
  double get strokeWidth => data.strokeWidth;
  @override
  Offset get canvasPosition => data.position;
  @override
  Size get canvasSize => data.size;
}
