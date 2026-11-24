// Provides bounded ZIP transport for the shared transfer tree.

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/library/transfer/canvas_transfer.dart';

/// Reads a ZIP transfer after validating all headers and payloads.
final class ZipTransferSource implements TransferSource {
  ZipTransferSource(Uint8List bytes) : _bytes = _boundedZipCopy(bytes);

  final Uint8List _bytes;
  late final Future<List<TransferEntry>> _entries = _prepare();
  late final Map<String, Uint8List> _files;

  @override
  Future<List<TransferEntry>> entries() => _entries;

  @override
  Future<Uint8List> read(String path) async {
    await entries();
    final bytes = _files[path];
    if (bytes == null) throw FormatException('Unknown transfer path: $path');
    return Uint8List.fromList(bytes);
  }

  Future<List<TransferEntry>> _prepare() async {
    validateCanvasTransferSize(_bytes.length);
    late final ZipDirectory directory;
    try {
      directory = ZipDirectory()..read(InputMemoryStream(_bytes), verify: true);
    } on Object {
      throw const FormatException('Invalid ZIP archive');
    }
    if (directory.filePosition < 0 ||
        directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0 ||
        directory.totalCentralDirectoryEntriesOnThisDisk != directory.totalCentralDirectoryEntries ||
        directory.fileHeaders.length != directory.totalCentralDirectoryEntries) {
      throw const FormatException('Invalid ZIP archive');
    }
    final commentLength = _bytes[directory.filePosition + 20] | (_bytes[directory.filePosition + 21] << 8);
    if (directory.filePosition + 22 + commentLength != _bytes.length ||
        directory.centralDirectoryOffset + directory.centralDirectorySize != directory.filePosition) {
      throw const FormatException('Invalid ZIP archive');
    }

    final headers = <String, ZipFileHeader>{};
    final entries = <TransferEntry>[];
    var declaredTotal = 0;
    for (final header in directory.fileHeaders) {
      final name = header.filename;
      final compression = switch (header.compressionMethod) {
        ZipFile.zipCompressionStore => CompressionType.none,
        ZipFile.zipCompressionDeflate => CompressionType.deflate,
        ZipFile.zipCompressionBZip2 => CompressionType.bzip2,
        _ => throw FormatException('Unsupported ZIP compression: $name'),
      };
      final ZipFile? file;
      try {
        file = header.file;
      } on Object {
        throw FormatException('Invalid ZIP entry: $name');
      }
      final unixKind = header.versionMadeBy >> 8 == 3 ? (header.externalFileAttributes >> 28) & 0xf : 0;
      final isDirectory = name.endsWith('/') || unixKind == 4;
      final path = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
      if (file == null ||
          file.unsupportedMethod != null ||
          file.compressionMethod != compression ||
          header.generalPurposeBitFlag != file.flags ||
          header.crc32 != file.crc32 ||
          (header.generalPurposeBitFlag & (0x1 | 0x40 | 0x2000)) != 0 ||
          (header.externalFileAttributes & 0x400) != 0 ||
          header.diskNumberStart != 0 ||
          (unixKind != 0 && unixKind != 8 && unixKind != 4) ||
          (unixKind == 8 && isDirectory)) {
        throw FormatException('Invalid ZIP entry: $name');
      }
      if (path.isEmpty || header.compressedSize < 0 || header.uncompressedSize < 0) {
        throw FormatException('Invalid ZIP entry: $name');
      }
      if (file.getStream(decompress: false).length != header.compressedSize) {
        throw FormatException('Invalid ZIP entry: $name');
      }
      if ((file.flags & 0x8) != 0 &&
          (file.compressedSize != header.compressedSize || file.uncompressedSize != header.uncompressedSize)) {
        throw FormatException('Invalid ZIP entry: $name');
      }
      if (isDirectory && (header.compressedSize != 0 || header.uncompressedSize != 0)) {
        throw FormatException('Invalid ZIP directory: $path');
      }

      final kind = isDirectory ? TransferEntryKind.directory : TransferEntryKind.regularFile;
      final entry = TransferEntry(path: path, kind: kind, size: isDirectory ? 0 : header.uncompressedSize);
      if (kind == TransferEntryKind.regularFile) {
        declaredTotal += header.uncompressedSize;
        validateCanvasTransferSize(declaredTotal);
        if (_isAttachmentPath(path)) {
          validateAttachmentPath(path);
          validateAttachmentSize(header.uncompressedSize, 'Attachment exceeds 10 MiB: $path');
        }
        if (!_insideGitMetadata(path) && path.endsWith('.canvas.json') && _insideAttachmentNamespace(path)) {
          throw FormatException('Canvas inside attachments namespace: $path');
        }
      }
      headers[path] = header;
      entries.add(entry);
    }
    validateTransferEntries(entries);

    final files = <String, Uint8List>{};
    for (final entry in entries) {
      if (entry.kind == TransferEntryKind.directory) {
        if (headers[entry.path]!.crc32 != getCrc32(Uint8List(0))) {
          throw FormatException('Damaged ZIP entry: ${entry.path}');
        }
        continue;
      }
      files[entry.path] = _checkedZipBytes(headers[entry.path]!, entry.path);
    }
    _files = files;
    return List.unmodifiable(entries);
  }
}

/// Encodes a validated root-relative tree as a ZIP archive.
Uint8List encodeTransferZip(TransferTree tree) {
  final entries = <TransferEntry>[
    for (final entry in tree.files.entries)
      TransferEntry(path: entry.key, kind: TransferEntryKind.regularFile, size: entry.value.length),
    for (final path in tree.directories) TransferEntry(path: path, kind: TransferEntryKind.directory),
  ];
  validateTransferEntries(entries);
  var expandedTotal = 0;
  for (final entry in tree.files.entries) {
    expandedTotal += entry.value.length;
    validateCanvasTransferSize(expandedTotal);
    if (_isAttachmentPath(entry.key)) {
      validateAttachmentPath(entry.key);
      validateAttachmentSize(entry.value.length, 'Attachment exceeds 10 MiB: ${entry.key}');
    }
  }

  final archive = Archive();
  for (final path in tree.directories.toList()..sort()) {
    archive.add(ArchiveFile.directory('$path/'));
  }
  for (final path in tree.files.keys.toList()..sort()) {
    archive.add(ArchiveFile.bytes(path, tree.files[path]!));
  }
  final bytes = ZipEncoder().encodeBytes(archive);
  validateCanvasTransferSize(bytes.length);
  return bytes;
}

/// Selects the shared input adapter from a selected filename.
TransferSource transferSourceFromFile({required String name, required Uint8List bytes}) {
  if (name.endsWith('.zip')) return ZipTransferSource(bytes);
  if (name.endsWith('.canvas.json')) return StandaloneCanvasTransferSource(name: name, bytes: bytes);
  throw const FormatException('Unsupported transfer file');
}

Uint8List _checkedZipBytes(ZipFileHeader header, String path) {
  final output = _BoundedZipOutput(header.uncompressedSize);
  try {
    if (header.compressionMethod == ZipFile.zipCompressionDeflate) {
      Inflate.stream(header.file!.getStream(decompress: false), output: output);
    } else {
      header.file!.decompress(output);
    }
  } on Object {
    throw FormatException('Damaged ZIP entry: $path');
  }
  final bytes = output.getBytes();
  if (bytes.length != header.uncompressedSize || getCrc32(bytes) != header.crc32) {
    throw FormatException('Damaged ZIP entry: $path');
  }
  return bytes;
}

final class _BoundedZipOutput extends OutputStream {
  _BoundedZipOutput(this.maximumBytes) : _output = OutputMemoryStream(), super(byteOrder: ByteOrder.littleEndian);

  final int maximumBytes;
  final OutputMemoryStream _output;

  @override
  int get length => _output.length;

  @override
  void clear() => _output.clear();

  @override
  void flush() => _output.flush();

  @override
  void writeByte(int value) {
    _check(1);
    _output.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    _output.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    _output.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    _output.writeBackReference(distance, count);
  }

  @override
  Uint8List subset(int start, [int? end]) => _output.subset(start, end);

  @override
  Uint8List getBytes() => _output.getBytes();

  void _check(int additionalBytes) {
    if (additionalBytes > maximumBytes - length) {
      throw const FormatException('ZIP entry exceeds its declared size');
    }
  }
}

bool _isAttachmentPath(String path) {
  final segments = path.split('/');
  return segments.length >= 2 && segments[segments.length - 2] == 'attachments';
}

bool _insideGitMetadata(String path) => path.split('/').contains('.git');

bool _insideAttachmentNamespace(String path) => path.split('/').contains('attachments');

Uint8List _boundedZipCopy(Uint8List bytes) {
  validateCanvasTransferSize(bytes.length);
  return Uint8List.fromList(bytes);
}
