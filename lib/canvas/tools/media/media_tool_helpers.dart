// Provides shared media transitions, drag handling, and image decoding.
// Used by the media tool, image surface, URL panel, and media model.

part of 'media_tool.dart';

// ---------- Transitions ----------

Widget _mediaTransition(
  Widget child,
  Animation<double> animation, [
  Alignment alignment = Alignment.topCenter,
]) => FadeTransition(
  opacity: animation,
  child: ScaleTransition(
    scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
    alignment: alignment,
    child: child,
  ),
);
