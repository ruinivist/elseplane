// Adapts persisted arrow data to selectable canvas geometry.
// Used by the editor's element, movement, and rendering flows.

part of 'arrow_tool.dart';

// ---------- Models ----------

/// Adapts persisted arrow points to canvas geometry and movement.
/// Used by the canvas selection and arrow rendering flows.
class ArrowModel extends CanvasElementModel<ArrowElementData> {
  ArrowModel(super.data);

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

  bool setPoint(int index, Offset position) {
    final current = point(index);
    final next = index == 0
        ? minimumLengthArrowPoint(position, end, start)
        : index == pointCount - 1
        ? minimumLengthArrowPoint(position, start, end)
        : position;
    if (next == current) return false;
    if (index == 0) {
      replaceData(data.copyWith(start: next));
    } else if (index == pointCount - 1) {
      replaceData(data.copyWith(end: next));
    } else {
      replaceData(data.copyWith(controls: List.of(data.controls)..[index - 1] = next));
    }
    return true;
  }

  Color get color => data.color;

  set color(Color value) {
    if (data.color == value) return;
    replaceData(data.copyWith(color: value));
  }

  ArrowStrokeStyle get strokeStyle => data.strokeStyle;

  set strokeStyle(ArrowStrokeStyle value) {
    if (data.strokeStyle == value) return;
    replaceData(data.copyWith(strokeStyle: value));
  }

  double get strokeWidth => data.strokeWidth;

  set strokeWidth(double value) {
    if (data.strokeWidth == value) return;
    replaceData(data.copyWith(strokeWidth: value));
  }

  @override
  void moveBy(Offset delta) {
    if (delta == Offset.zero) return;
    replaceData(
      data.copyWith(
        start: data.start + delta,
        controls: [for (final control in data.controls) control + delta],
        end: data.end + delta,
      ),
    );
  }
}
