import 'dart:typed_data';

import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transfer values own unmodifiable collection and byte copies', () {
    const documentPath = 'Projects/Map.canvas.json';
    final input = Uint8List.fromList([1, 2, 3]);
    final tree = TransferTree(files: {documentPath: input}, directories: {'Projects'});
    input[0] = 9;

    expect(tree.files[documentPath], [1, 2, 3]);
    expect(() => tree.files[documentPath]![0] = 8, throwsUnsupportedError);
    expect(tree.files.clear, throwsUnsupportedError);
    expect(tree.directories.clear, throwsUnsupportedError);

    final image = Uint8List.fromList([4]);
    final candidate = TransferImport(
      canvases: {documentPath: CanvasLibrary.emptyDocument},
      attachments: {'Projects/attachments/123e4567-e89b-42d3-a456-426614174000.png': image},
      directories: {'Projects'},
      skippedCanvases: const [TransferIssue(path: 'Skipped.canvas.json', reason: 'Invalid JSON')],
    );
    image[0] = 5;
    expect(candidate.attachments.values.single, [4]);
    expect(candidate.skippedCanvases.clear, throwsUnsupportedError);

    final merge = TransferMerge(
      candidate: candidate,
      expectedChangeRevision: 7,
      overwritePaths: {'Projects/Map.canvas.json'},
    );
    expect(merge.overwritePaths.clear, throwsUnsupportedError);
    final result = TransferImportResult(
      skippedCanvases: candidate.skippedCanvases,
      writtenImagePaths: const ['Projects/attachments/image.png'],
      metadataSaved: false,
      failure: const TransferFailure(
        path: 'Projects/attachments/image.png',
        reason: 'Write failed',
        stage: TransferFailureStage.imageWrite,
      ),
    );
    expect(result.writtenImagePaths.clear, throwsUnsupportedError);
  });

  test('accepts explicit parent directories and adds implied directories', () {
    final directories = validateTransferEntries([
      TransferEntry(path: 'Projects', kind: TransferEntryKind.directory),
      TransferEntry(path: 'Projects/Maps/Map.canvas.json', kind: TransferEntryKind.regularFile, size: 4),
    ]);

    expect(directories, {'Projects', 'Projects/Maps'});
  });

  test('rejects duplicate, unsafe, and file-prefix paths while preserving case', () {
    final duplicate = TransferEntry(path: 'Map.canvas.json', kind: TransferEntryKind.regularFile);
    expect(() => validateTransferEntries([duplicate, duplicate]), throwsFormatException);
    expect(
      () => validateTransferEntries([
        TransferEntry(path: 'Projects', kind: TransferEntryKind.regularFile),
        TransferEntry(path: 'Projects/Map.canvas.json', kind: TransferEntryKind.regularFile),
      ]),
      throwsFormatException,
    );
    expect(
      () => validateTransferEntries([
        TransferEntry(path: 'Projects', kind: TransferEntryKind.regularFile),
        TransferEntry(path: 'Projects', kind: TransferEntryKind.directory),
      ]),
      throwsFormatException,
    );
    for (final path in [
      '',
      '/Map.canvas.json',
      'Projects/../Map.canvas.json',
      r'Projects\Map.canvas.json',
      'Projects//Map.canvas.json',
    ]) {
      expect(
        () => TransferEntry(path: path, kind: TransferEntryKind.regularFile),
        throwsFormatException,
        reason: path,
      );
    }
    expect(
      validateTransferEntries([
        TransferEntry(path: 'School/Map.canvas.json', kind: TransferEntryKind.regularFile),
        TransferEntry(path: 'school/Map.canvas.json', kind: TransferEntryKind.regularFile),
      ]),
      {'School', 'school'},
    );
  });
}
