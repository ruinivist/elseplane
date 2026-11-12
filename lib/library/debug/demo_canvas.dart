// Loads the bundled demo project for debug builds.
// Used by the canvas picker to populate a new canvas.

import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/library/transfer/canvas_transfer_zip.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<TransferImport> loadDemoCanvas() async {
  if (!kDebugMode) throw UnsupportedError('Demo is only available in debug builds');
  final data = await rootBundle.load('assets/demo/canvas.elseplane.zip');
  final transfer = await decodeTransfer(
    ZipTransferSource(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)),
  );
  if (transfer.canvases.length != 1 ||
      !transfer.canvases.containsKey('Demo.canvas.json') ||
      transfer.skippedCanvases.isNotEmpty) {
    throw const FormatException('Invalid bundled demo canvas');
  }
  return transfer;
}
