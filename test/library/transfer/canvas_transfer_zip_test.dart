import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';
import 'package:elseplane/library/transfer/canvas_transfer_zip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ZIP round-trip retains explicit empty directories and literal paths', () async {
    final tree = TransferTree(
      files: {
        'École/Map.canvas.json': Uint8List.fromList(utf8.encode('{}')),
        'École/attachments/123e4567-e89b-42d3-a456-426614174000.png': Uint8List.fromList([1, 2, 3]),
      },
      directories: {'École', 'École/Empty folder'},
    );

    final bytes = encodeTransferZip(tree);
    expect(bytes.length, lessThanOrEqualTo(canvasTransferMaximumBytes));
    final decoded = await decodeTransfer(ZipTransferSource(bytes));
    expect(decoded.directories, {'École', 'École/Empty folder'});
    expect(decoded.canvases, isEmpty);
  });

  test('file selection chooses ZIP or standalone transfer source by suffix', () {
    expect(
      transferSourceFromFile(name: 'Map.canvas.json', bytes: Uint8List(0)),
      isA<StandaloneCanvasTransferSource>(),
    );
    expect(transferSourceFromFile(name: 'library.zip', bytes: Uint8List(0)), isA<ZipTransferSource>());
    expect(() => transferSourceFromFile(name: 'document.json', bytes: Uint8List(0)), throwsFormatException);
  });

  for (final compression in CompressionType.values) {
    test('ZIP input verifies supported $compression compression and CRC', () async {
      final bytes = _zip({
        'README': Uint8List.fromList([1, 2, 3, 4]),
      }, compression: compression);
      final entries = await ZipTransferSource(bytes).entries();
      expect(entries.single.path, 'README');
      expect(entries.single.size, 4);
    });
  }

  test('ZIP preflight rejects unsafe paths, duplicate names, links, and encryption', () async {
    await expectLater(ZipTransferSource(_zip({'../outside': Uint8List(0)})).entries(), throwsFormatException);
    await expectLater(
      ZipTransferSource(_duplicateFirst(_zip({'README': Uint8List(0)}))).entries(),
      throwsFormatException,
    );
    await expectLater(
      ZipTransferSource(_markFirstAsSymlink(_zip({'README': Uint8List(0)}))).entries(),
      throwsFormatException,
    );
    await expectLater(
      ZipTransferSource(_markFirstEncrypted(_zip({'README': Uint8List(0)}))).entries(),
      throwsFormatException,
    );
  });

  test('validates integrity of ignored regular files before source preparation succeeds', () async {
    final bytes = _zip({
      'README': Uint8List.fromList([1, 2, 3]),
    });
    await expectLater(ZipTransferSource(_corruptFirstCrc(bytes)).entries(), throwsFormatException);
  });

  test('rejects local and central header disagreements', () async {
    final valid = _zip({
      'README': Uint8List.fromList([1, 2, 3]),
    });
    for (final corrupted in [
      _changeLocalFilename(valid),
      _changeCentralFilename(valid),
      _changeLocalFlags(valid),
      _changeCentralFlags(valid),
      _changeLocalCompression(valid),
      _changeCentralCompression(valid),
      _changeLocalCrc(valid),
      _changeCentralCrc(valid),
    ]) {
      await expectLater(ZipTransferSource(corrupted).entries(), throwsFormatException);
    }
  });

  test('rejects malformed EOCD records, multi-disk metadata, and inconsistent entry counts', () async {
    final valid = _zip({
      'README': Uint8List.fromList([1, 2, 3]),
    });
    final eocd = _eocdOffset(valid);
    for (final corrupted in [
      _changeEocdSignature(valid),
      _changeEocdCommentLength(valid),
      _changeEocdCentralDirectorySize(valid),
      _changeEocdCentralDirectoryOffset(valid),
      _changeEocdDisk(valid, 4),
      _changeEocdDisk(valid, 6),
      _changeEocdEntryCount(valid, 8),
      _changeEocdEntryCount(valid, 10),
    ]) {
      expect(_readUint32(valid, eocd), 0x06054b50);
      await expectLater(ZipTransferSource(corrupted).entries(), throwsFormatException);
    }
  });

  test('rejects declared overages and stops inflation at an understated entry size', () async {
    final bytes = _zip({'README': Uint8List.fromList(List.filled(1024 * 1024, 0x41))});
    await expectLater(
      ZipTransferSource(_setFirstUncompressedSize(bytes, canvasTransferMaximumBytes + 1)).entries(),
      throwsFormatException,
    );
    await expectLater(ZipTransferSource(_setFirstUncompressedSize(bytes, 32)).entries(), throwsFormatException);
  });
}

Uint8List _zip(Map<String, Uint8List> files, {CompressionType compression = CompressionType.deflate}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value)..compression = compression);
  }
  return ZipEncoder().encodeBytes(archive);
}

int _eocdOffset(Uint8List bytes) {
  for (var offset = bytes.length - 22; offset >= 0; offset--) {
    if (_readUint32(bytes, offset) == 0x06054b50) return offset;
  }
  throw StateError('Missing ZIP end record');
}

int _readUint16(Uint8List bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8);

int _readUint32(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);

void _writeUint16(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}

void _writeUint32(Uint8List bytes, int offset, int value) {
  for (var byte = 0; byte < 4; byte++) {
    bytes[offset + byte] = (value >> (byte * 8)) & 0xff;
  }
}

Uint8List _changeLocalFilename(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final local = _localHeaderOffset(bytes);
  final nameLength = _readUint16(bytes, local + 26);
  bytes[local + 30 + nameLength - 1] ^= 1;
  return bytes;
}

Uint8List _changeCentralFilename(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final central = _centralHeaderOffset(bytes);
  final nameLength = _readUint16(bytes, central + 28);
  bytes[central + 46 + nameLength - 1] ^= 1;
  return bytes;
}

Uint8List _changeLocalFlags(Uint8List source) => _changeHeaderUint16(source, _localHeaderOffset, 6, 2);

Uint8List _changeCentralFlags(Uint8List source) => _changeHeaderUint16(source, _centralHeaderOffset, 8, 2);

Uint8List _changeLocalCompression(Uint8List source) => _changeHeaderUint16(source, _localHeaderOffset, 8, 0);

Uint8List _changeCentralCompression(Uint8List source) => _changeHeaderUint16(source, _centralHeaderOffset, 10, 0);

Uint8List _changeLocalCrc(Uint8List source) => _changeHeaderUint32(source, _localHeaderOffset, 14);

Uint8List _changeCentralCrc(Uint8List source) => _changeHeaderUint32(source, _centralHeaderOffset, 16);

Uint8List _changeHeaderUint16(
  Uint8List source,
  int Function(Uint8List) offset,
  int fieldOffset,
  int value,
) {
  final bytes = Uint8List.fromList(source);
  final header = offset(bytes);
  _writeUint16(bytes, header + fieldOffset, value);
  return bytes;
}

Uint8List _changeHeaderUint32(Uint8List source, int Function(Uint8List) offset, int fieldOffset) {
  final bytes = Uint8List.fromList(source);
  final header = offset(bytes);
  _writeUint32(bytes, header + fieldOffset, _readUint32(bytes, header + fieldOffset) ^ 1);
  return bytes;
}

Uint8List _changeEocdSignature(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  _writeUint32(bytes, _eocdOffset(bytes), 0);
  return bytes;
}

Uint8List _changeEocdCommentLength(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  _writeUint16(bytes, _eocdOffset(bytes) + 20, 1);
  return bytes;
}

Uint8List _changeEocdCentralDirectorySize(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final eocd = _eocdOffset(bytes);
  _writeUint32(bytes, eocd + 12, _readUint32(bytes, eocd + 12) - 1);
  return bytes;
}

Uint8List _changeEocdCentralDirectoryOffset(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final eocd = _eocdOffset(bytes);
  _writeUint32(bytes, eocd + 16, _readUint32(bytes, eocd + 16) + 1);
  return bytes;
}

Uint8List _changeEocdDisk(Uint8List source, int fieldOffset) {
  final bytes = Uint8List.fromList(source);
  _writeUint16(bytes, _eocdOffset(bytes) + fieldOffset, 1);
  return bytes;
}

Uint8List _changeEocdEntryCount(Uint8List source, int fieldOffset) {
  final bytes = Uint8List.fromList(source);
  final eocd = _eocdOffset(bytes);
  _writeUint16(bytes, eocd + fieldOffset, _readUint16(bytes, eocd + fieldOffset) + 1);
  return bytes;
}

int _localHeaderOffset(Uint8List bytes) => _readUint32(bytes, _centralHeaderOffset(bytes) + 42);

int _centralHeaderOffset(Uint8List bytes) => _readUint32(bytes, _eocdOffset(bytes) + 16);

Uint8List _duplicateFirst(Uint8List source) {
  final eocd = _eocdOffset(source);
  final central = _readUint32(source, eocd + 16);
  final recordLength =
      46 + _readUint16(source, central + 28) + _readUint16(source, central + 30) + _readUint16(source, central + 32);
  final result = Uint8List(source.length + recordLength)
    ..setRange(0, eocd, source)
    ..setRange(eocd, eocd + recordLength, source, central)
    ..setRange(eocd + recordLength, source.length + recordLength, source, eocd);
  final newEocd = eocd + recordLength;
  _writeUint16(result, newEocd + 8, _readUint16(source, eocd + 8) + 1);
  _writeUint16(result, newEocd + 10, _readUint16(source, eocd + 10) + 1);
  _writeUint32(result, newEocd + 12, _readUint32(source, eocd + 12) + recordLength);
  return result;
}

Uint8List _markFirstAsSymlink(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final central = _readUint32(bytes, _eocdOffset(bytes) + 16);
  _writeUint16(bytes, central + 4, (3 << 8) | 20);
  _writeUint32(bytes, central + 38, 0xa1ff0000);
  return bytes;
}

Uint8List _markFirstEncrypted(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final central = _readUint32(bytes, _eocdOffset(bytes) + 16);
  final local = _readUint32(bytes, central + 42);
  _writeUint16(bytes, central + 8, _readUint16(bytes, central + 8) | 1);
  _writeUint16(bytes, local + 6, _readUint16(bytes, local + 6) | 1);
  return bytes;
}

Uint8List _corruptFirstCrc(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final central = _readUint32(bytes, _eocdOffset(bytes) + 16);
  final local = _readUint32(bytes, central + 42);
  _writeUint32(bytes, central + 16, 0);
  _writeUint32(bytes, local + 14, 0);
  return bytes;
}

Uint8List _setFirstUncompressedSize(Uint8List source, int size) {
  final bytes = Uint8List.fromList(source);
  final central = _readUint32(bytes, _eocdOffset(bytes) + 16);
  final local = _readUint32(bytes, central + 42);
  _writeUint32(bytes, central + 24, size);
  _writeUint32(bytes, local + 22, size);
  return bytes;
}
