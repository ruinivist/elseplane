import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _source1 = 'Source/attachments/123e4567-e89b-42d3-a456-426614174000.png';
const _source2 = 'Source/attachments/123e4567-e89b-42d3-a456-426614174001.png';
const _destination1 = 'Destination/attachments/123e4567-e89b-42d3-a456-426614174000.png';
const _destination2 = 'Destination/attachments/123e4567-e89b-42d3-a456-426614174001.png';

void main() {
  test('copies available bytes, reuses equal bytes, and retains sources', () async {
    final store = _Store({
      _source1: Uint8List.fromList([0, 1, 2]),
      _source2: Uint8List.fromList([9]),
    })..files[_destination2] = Uint8List.fromList([9]);
    final attempted = <String>[];

    final written = await copyAttachmentPaths(store, {
      _source1: _destination1,
      _source2: _destination2,
      'Source/attachments/123e4567-e89b-42d3-a456-426614174002.png':
          'Destination/attachments/123e4567-e89b-42d3-a456-426614174002.png',
    }, beforeWrite: attempted.add);

    expect(written, [_destination1]);
    expect(attempted, [_destination1]);
    expect(store.files[_source1], [0, 1, 2]);
    expect(store.files[_destination1], [0, 1, 2]);
    expect(store.writes, [_destination1]);
    expect(written.clear, throwsUnsupportedError);
  });

  test('preflights every source and destination before reporting a byte conflict', () async {
    final store = _Store({
      _source1: Uint8List.fromList([1]),
      _source2: Uint8List.fromList([2]),
    })..files[_destination2] = Uint8List.fromList([3]);
    final attempted = <String>[];

    await expectLater(
      copyAttachmentPaths(store, {_source1: _destination1, _source2: _destination2}, beforeWrite: attempted.add),
      throwsA(isA<FormatException>().having((error) => error.message, 'path', contains(_destination2))),
    );

    expect(store.reads, unorderedEquals([_source1, _source2, _destination1, _destination2]));
    expect(store.writes, isEmpty);
    expect(attempted, isEmpty);
  });

  test('deduplicates equal source bytes targeting the same destination', () async {
    final bytes = Uint8List.fromList([1, 2]);
    final store = _Store({_source1: bytes, _source2: Uint8List.fromList(bytes)});

    final written = await copyAttachmentPaths(store, {_source1: _destination1, _source2: _destination1});

    expect(written, [_destination1]);
    expect(store.writes, [_destination1]);
  });

  test('source read errors propagate before writes', () async {
    final store = _Store({
      _source1: Uint8List.fromList([1]),
    })..failedRead = _source2;

    await expectLater(
      copyAttachmentPaths(store, {_source1: _destination1, _source2: _destination2}),
      throwsStateError,
    );

    expect(store.writes, isEmpty);
  });

  test('reports attempted keys around a partial write failure', () async {
    final store = _Store({
      _source1: Uint8List.fromList([1]),
      _source2: Uint8List.fromList([2]),
    })..failedWrite = _destination2;
    final attempted = <String>[];

    await expectLater(
      copyAttachmentPaths(store, {_source1: _destination1, _source2: _destination2}, beforeWrite: attempted.add),
      throwsStateError,
    );

    expect(attempted, [_destination1, _destination2]);
    expect(store.files[_destination1], [1]);
    expect(store.files, contains(_source1));
    expect(store.files, contains(_source2));
  });

  test('rejects invalid keys and oversized bytes before any write', () async {
    final store = _Store({_source1: Uint8List(attachmentMaximumBytes + 1)});

    await expectLater(copyAttachmentPaths(store, {_source1: '../invalid'}), throwsFormatException);
    expect(store.reads, isEmpty);
    await expectLater(copyAttachmentPaths(store, {_source1: _destination1}), throwsFormatException);
    expect(store.writes, isEmpty);
  });
}

final class _Store implements AttachmentStore {
  _Store([Map<String, Uint8List>? initial]) : files = {...?initial};

  final Map<String, Uint8List> files;
  final reads = <String>[];
  final writes = <String>[];
  String? failedRead;
  String? failedWrite;

  @override
  Future<void> delete(String path) async => files.remove(path);

  @override
  Future<Uint8List> read(String path) async => files[path]!;

  @override
  Future<Uint8List?> readIfExists(String path) async {
    reads.add(path);
    if (path == failedRead) throw StateError('read failed');
    return files[path];
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    writes.add(path);
    if (path == failedWrite) throw StateError('write failed');
    files[path] = Uint8List.fromList(bytes);
  }
}
