// Retains cached pen geometry for accepted stroke values.
// Used by stroke views while the session owns movement and selection.

part of 'pen_tool.dart';

// ---------- Models ----------

/// Adapts persisted pen data to a rendered path and canvas movement.
/// Used by selection, hit testing, and stroke rendering.
class PenStrokeModel extends CanvasElementModel<PenElementData> {
  PenStrokeModel(super.session, super.data) : path = createPenPath(data.points, data.width, data.streamline);

  Path path;

  @override
  void synchronizeData(PenElementData previous, {required bool restored}) {
    if (identical(previous.points, data.points) &&
        previous.width == data.width &&
        previous.streamline == data.streamline) {
      return;
    }
    path = createPenPath(data.points, data.width, data.streamline);
  }

  @override
  Offset get canvasPosition => data.position;

  @override
  Size get canvasSize => data.size;
}
