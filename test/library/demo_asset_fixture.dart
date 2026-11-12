import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/library/transfer/canvas_transfer_zip.dart';
import 'package:flutter_test/flutter_test.dart';

const demoImagePath = 'attachments/00000000-0000-4000-8000-000000000001.jpg';
final demoImageBytes = Uint8List.fromList([1, 2, 3]);
int demoAssetReadCount = 0;

void installDemoAssetFixture() {
  demoAssetReadCount = 0;
  final document = CanvasDocument(
    background: CanvasBackgroundKind.plain,
    elements: [MediaElementData(id: 'demo-image', position: Offset.zero, width: 120, url: demoImagePath)],
  );
  final bytes = encodeTransferZip(
    TransferTree(
      files: {
        'Demo.canvas.json': Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(document.toJson())),
        ),
        demoImagePath: demoImageBytes,
      },
    ),
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) {
    if (utf8.decode(message!.buffer.asUint8List()) != 'assets/demo/canvas.elseplane.zip') return null;
    demoAssetReadCount++;
    return Future.value(ByteData.sublistView(bytes));
  });
}
