// Adapts persisted shape data to selectable and resizable canvas state.
// Used by shape rendering, selection, transformation, and persistence flows.

part of 'shape_tool.dart';

// ---------- Models ----------

/// Adapts persisted shape data to selectable and resizable canvas geometry.
/// Used by the canvas selection and shape rendering flows.
class ShapeModel extends CanvasElementModel<ShapeElementData> {
  ShapeModel(super.data);

  ShapeKind get kind => data.kind;

  set kind(ShapeKind value) {
    if (data.kind == value) return;
    replaceData(data.copyWith(kind: value));
  }

  Color get strokeColor => data.strokeColor;

  set strokeColor(Color value) {
    if (data.strokeColor == value) return;
    replaceData(data.copyWith(strokeColor: value));
  }

  Color? get fillColor => data.fillColor;

  set fillColor(Color? value) {
    if (data.fillColor == value) return;
    replaceData(data.copyWith(fillColor: value, clearFillColor: value == null));
  }

  double get strokeWidth => data.strokeWidth;

  set strokeWidth(double value) {
    if (data.strokeWidth == value) return;
    replaceData(data.copyWith(strokeWidth: value));
  }

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize => data.size;

  @override
  void moveBy(Offset delta) {
    if (delta == Offset.zero) return;
    replaceData(data.copyWith(position: data.position + delta));
  }

  void resizeBy(Offset delta) {
    final size = Size(
      math.max(shapeMinimumSize.width, data.size.width + delta.dx),
      math.max(shapeMinimumSize.height, data.size.height + delta.dy),
    );
    if (size == data.size) return;
    replaceData(data.copyWith(size: size));
  }
}
