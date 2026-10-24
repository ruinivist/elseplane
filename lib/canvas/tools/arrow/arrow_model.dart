// Projects saved arrow points into paths and bounds.
// Used by arrow views while the session owns edits and interaction state.

part of 'arrow_tool.dart';

// ---------- Models ----------

/// Adapts persisted arrow points to canvas geometry and movement.
/// Used by the canvas selection and arrow rendering flows.
class ArrowModel extends CanvasElementModel<ArrowElementData> {
  ArrowModel(super.session, super.data);

  ArrowGeometry get geometry => ArrowGeometry(
    start: data.start,
    controls: data.controls,
    end: data.end,
  );

  Rect get bounds => geometry.bounds;

  ArrowGeometry get localGeometry => geometry.shift(-bounds.topLeft);

  @override
  Offset get canvasPosition => bounds.topLeft;

  @override
  Size get canvasSize => bounds.size;

  Offset get start => data.start;

  List<Offset> get controls => data.controls;

  Offset get end => data.end;

  int get pointCount => data.controls.length + 2;

  Offset point(int index) {
    RangeError.checkValidIndex(index, this, 'index', pointCount);
    if (index == 0) return start;
    if (index == pointCount - 1) return end;
    return data.controls[index - 1];
  }

  Color get color => data.color;
  ArrowStrokeStyle get strokeStyle => data.strokeStyle;
  double get strokeWidth => data.strokeWidth;
}
