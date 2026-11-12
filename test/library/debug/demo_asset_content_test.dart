// Checks the checked-in demo ZIP independently of the browser asset channel.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/library/transfer/canvas_transfer_zip.dart';
import 'package:flutter_test/flutter_test.dart';

const _documentPath = 'Demo.canvas.json';
const _imagePath = 'attachments/00000000-0000-4000-8000-000000000001.jpg';

void main() {
  test('bundled demo keeps its direct root document and image bytes', () async {
    final archive = ZipTransferSource(
      Uint8List.fromList(await File('assets/demo/canvas.elseplane.zip').readAsBytes()),
    );
    expect((await archive.entries()).map((entry) => entry.path).toSet(), {_documentPath, _imagePath});
    final transfer = await decodeTransfer(archive);
    final document = transfer.canvases[_documentPath]!;

    expect(transfer.canvases.keys, {_documentPath});
    expect(transfer.skippedCanvases, isEmpty);
    expect(transfer.directories, isEmpty);
    expect(transfer.attachments.keys, {_imagePath});
    expect(transfer.attachments[_imagePath], hasLength(68880));
    final sourceDocument = jsonDecode(utf8.decode(await archive.read(_documentPath))) as Map<String, dynamic>;
    final sourceElements = sourceDocument['elements'] as List<dynamic>;
    expect(sourceDocument['version'], 8);
    expect(document.background.name, 'dotGrid');
    expect((sourceElements.first as Map<String, dynamic>)['markdown'], contains('# A place for ideas'));
    expect(
      (sourceElements.singleWhere((element) => (element as Map<String, dynamic>)['id'] == 'image')
          as Map<String, dynamic>)['url'],
      _imagePath,
    );
    expect(document.elements.map((element) => element.id), [
      'headings',
      'paragraphs',
      'lists',
      'table',
      'code',
      'image',
      'rectangle',
      'ellipse',
      'diamond',
      'solid-arrow',
      'dashed-arrow',
      'pen',
    ]);
  });
}
