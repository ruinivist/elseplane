// Validates, encodes, and decodes portable canvas project archives.
// Used by the editor's import and export flows.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/image_import.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:flutter_markdown_plus/latex.dart';
import 'package:markdown/markdown.dart' as md;

// ---------- Limits ----------

const int canvasProjectMaximumBytes = 140 * 1024 * 1024;

// ---------- Validation ----------

void validateCanvasProjectSize(int length) {
  if (length > canvasProjectMaximumBytes) {
    throw const FormatException('Project exceeds 140 MiB');
  }
}

// ---------- Models ----------

/// Holds a decoded canvas document and all referenced attachment bytes.
/// Returned by project import for replacement of editor persistence.
final class CanvasProject {
  const CanvasProject({required this.document, required this.attachments});

  final CanvasDocument document;
  final Map<String, Uint8List> attachments;
}

// ---------- Attachment discovery ----------

Set<String> canvasAttachmentPaths(CanvasDocument document) {
  final paths = <String>{};
  for (final element in document.elements) {
    if (element case TextElementData(:final markdown)) {
      for (final image in _markdownImages(markdown)) {
        final path = image.attributes['src']!;
        if (attachmentPathPattern.hasMatch(path)) paths.add(path);
      }
    } else if (element case MediaElementData(:final url)) {
      final path = url.trim();
      if (attachmentPathPattern.hasMatch(path)) paths.add(path);
    }
  }
  return paths;
}

// ---------- Encoding and decoding ----------

CanvasDocument rebaseCanvasDocumentAttachments(CanvasDocument source, Map<String, String> replacements) {
  return source.copyWith(
    elements: [
      for (final element in source.elements)
        switch (element) {
          MediaElementData() => element.copyWith(url: replacements[element.url.trim()] ?? element.url),
          TextElementData() => element.copyWith(
            markdown: _rebaseMarkdownAttachments(element.markdown, replacements),
          ),
          _ => element,
        },
    ],
  );
}

/// Encodes a document and its referenced attachments as a portable ZIP project.
/// Used by the canvas export flow before saving to the host file system.
Future<Uint8List> encodeCanvasProject(
  CanvasDocument document,
  AttachmentStore store,
) async {
  final paths = canvasAttachmentPaths(document).toList()..sort();
  final archive = Archive();
  final documentBytes = Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(document.toJson())),
  );
  var totalBytes = documentBytes.length;
  validateCanvasProjectSize(totalBytes);
  archive.add(ArchiveFile.bytes('document.json', documentBytes));

  for (final path in paths) {
    final bytes = await store.read(path);
    await validateCanvasAttachment(path, bytes);
    totalBytes += bytes.length;
    validateCanvasProjectSize(totalBytes);
    archive.add(ArchiveFile.bytes(path, bytes));
  }

  final bytes = ZipEncoder().encodeBytes(archive);
  validateCanvasProjectSize(bytes.length);
  return bytes;
}

/// Validates and decodes a portable project and all embedded attachments.
/// Used by the canvas import flow before replacing editor state.
Future<CanvasProject> decodeCanvasProject(Uint8List bytes) async {
  validateCanvasProjectSize(bytes.length);

  late final ZipDirectory directory;
  try {
    directory = ZipDirectory()..read(InputMemoryStream(bytes));
  } on Object catch (error) {
    throw FormatException('Invalid project ZIP: $error');
  }
  if (directory.filePosition < 0 ||
      directory.numberOfThisDisk != 0 ||
      directory.diskWithTheStartOfTheCentralDirectory != 0 ||
      directory.totalCentralDirectoryEntriesOnThisDisk != directory.totalCentralDirectoryEntries ||
      directory.fileHeaders.length != directory.totalCentralDirectoryEntries) {
    throw const FormatException('Invalid project ZIP');
  }

  final headers = <String, ZipFileHeader>{};
  var documentCount = 0;
  var totalBytes = 0;
  for (final header in directory.fileHeaders) {
    final name = header.filename;
    final file = header.file;
    if (file == null ||
        file.filename != name ||
        header.generalPurposeBitFlag != file.flags ||
        header.compressionMethod !=
            switch (file.compressionMethod) {
              CompressionType.none => 0,
              CompressionType.deflate => 8,
              CompressionType.bzip2 => 12,
            } ||
        header.crc32 != file.crc32 ||
        header.generalPurposeBitFlag & 0x1 != 0 ||
        (header.versionMadeBy >> 8 == 3 && ((header.externalFileAttributes >> 28) & 0xf) == 0xa)) {
      throw const FormatException('Invalid ZIP entry');
    }
    if (header.compressionMethod != 0 && header.compressionMethod != 8 && header.compressionMethod != 12) {
      throw const FormatException('Unsupported ZIP compression');
    }
    if (name != 'document.json' && !attachmentPathPattern.hasMatch(name)) {
      throw FormatException('Unexpected ZIP entry: $name');
    }
    if (headers.containsKey(name)) throw const FormatException('Duplicate ZIP entry');
    if (name == 'document.json') documentCount++;
    if (header.uncompressedSize < 0 || header.compressedSize < 0) {
      throw const FormatException('Invalid ZIP entry size');
    }
    if (name != 'document.json') {
      validateAttachmentSize(header.uncompressedSize, 'Attachment exceeds 10 MiB: $name');
    }
    if (header.uncompressedSize > canvasProjectMaximumBytes - totalBytes) {
      throw const FormatException('Project exceeds 140 MiB uncompressed');
    }
    totalBytes += header.uncompressedSize;
    headers[name] = header;
  }
  if (documentCount != 1) throw const FormatException('ZIP must contain one document.json');

  late final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object catch (error) {
    throw FormatException('Invalid project ZIP: $error');
  }
  if (archive.length != headers.length) throw const FormatException('Duplicate ZIP entry');

  final documentEntry = archive.find('document.json');
  if (documentEntry == null || !documentEntry.isFile || documentEntry.isSymbolicLink) {
    throw const FormatException('ZIP must contain one document.json');
  }
  final documentBytes = _checkedZipBytes(documentEntry, headers['document.json']!);
  late final CanvasDocument document;
  try {
    document = CanvasDocument.fromJson(jsonDecode(utf8.decode(documentBytes, allowMalformed: false)));
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Invalid document.json: $error');
  }

  final referencedPaths = canvasAttachmentPaths(document);
  final archiveImagePaths = headers.keys.where((name) => name != 'document.json').toSet();
  if (archiveImagePaths.length != referencedPaths.length || !referencedPaths.containsAll(archiveImagePaths)) {
    throw const FormatException('Attachment references do not match the ZIP');
  }

  final attachments = <String, Uint8List>{};
  var actualTotalBytes = documentBytes.length;
  for (final entry in archive) {
    if (entry.name == 'document.json') continue;
    if (!entry.isFile || entry.isSymbolicLink) throw const FormatException('Invalid ZIP entry');
    final attachment = _checkedZipBytes(entry, headers[entry.name]!);
    validateAttachmentSize(attachment.length, 'Attachment exceeds 10 MiB: ${entry.name}');
    await validateCanvasAttachment(entry.name, attachment);
    actualTotalBytes += attachment.length;
    validateCanvasProjectSize(actualTotalBytes);
    attachments[entry.name] = attachment;
  }

  return CanvasProject(document: document, attachments: attachments);
}

Uint8List _checkedZipBytes(ArchiveFile entry, ZipFileHeader header) {
  final output = _CanvasProjectOutput(header.uncompressedSize);
  try {
    if (header.compressionMethod == 8) {
      Inflate.stream(header.file!.getStream(decompress: false), output: output);
    } else {
      entry.decompress(output);
    }
  } on Object catch (error) {
    throw FormatException('Damaged ZIP entry: ${entry.name} ($error)');
  }
  final bytes = output.getBytes();
  if (bytes.length != header.uncompressedSize || getCrc32(bytes) != header.crc32) {
    throw FormatException('Damaged ZIP entry: ${entry.name}');
  }
  return bytes;
}

final class _CanvasProjectOutput extends OutputStream {
  _CanvasProjectOutput(this.maximumBytes) : _output = OutputMemoryStream(), super(byteOrder: ByteOrder.littleEndian);

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

// ---------- Private helpers ----------

Iterable<md.Element> _markdownImages(String source) => _imageNodes(
  md.Document(
    extensionSet: md.ExtensionSet(
      [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, const LatexBlockSyntax()],
      [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexInlineSyntax()],
    ),
    encodeHtml: false,
  ).parse(source),
);

Iterable<md.Element> _imageNodes(List<md.Node> nodes) sync* {
  for (final node in nodes.whereType<md.Element>()) {
    if (node.tag == 'img') yield node;
    if (node.children != null) yield* _imageNodes(node.children!);
  }
}

String _rebaseMarkdownAttachments(String source, Map<String, String> replacements) {
  if (replacements.isEmpty) return source;
  final edits = <md.SourceRange, String>{};
  for (final image in _markdownImages(source)) {
    final path = image.attributes['src']!;
    final replacement = replacements[path];
    final range = image.destinationRange;
    if (attachmentPathPattern.hasMatch(path) && replacement != null && range != null) {
      edits[range] = replacement;
    }
  }
  if (edits.isEmpty) return source;
  final ranges = edits.keys.toList()..sort((a, b) => a.start.compareTo(b.start));
  final rebased = StringBuffer();
  var cursor = 0;
  for (final range in ranges) {
    rebased
      ..write(source.substring(cursor, range.start))
      ..write(edits[range]);
    cursor = range.end;
  }
  rebased.write(source.substring(cursor));
  return rebased.toString();
}
