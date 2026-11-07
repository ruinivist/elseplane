// Loads the bundled demo project for debug builds.
// Used by the canvas picker to populate a new canvas.

import 'package:elseplane/library/transfer/canvas_project.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<CanvasProject> loadDemoCanvas() {
  if (!kDebugMode) throw UnsupportedError('Demo is only available in debug builds');
  return rootBundle
      .load('assets/demo/canvas.elseplane.zip')
      .then(
        (data) => decodeCanvasProject(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
}
