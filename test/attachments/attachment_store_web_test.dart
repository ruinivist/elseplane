@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/attachments/attachment_store_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('all operations reject unsafe paths before root lookup', () async {
    var lookups = 0;
    final store = PlatformAttachmentStore(
      rootLookup: () async {
        lookups++;
        throw StateError('unexpected root lookup');
      },
    );

    for (final path in <String>[
      '',
      '/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'attachments/123e4567-e89b-42d3-a456-426614174000.png/',
      'Folder//attachments/123e4567-e89b-42d3-a456-426614174000.png',
      './attachments/123e4567-e89b-42d3-a456-426614174000.png',
      '../attachments/123e4567-e89b-42d3-a456-426614174000.png',
      r'Folder\attachments\123e4567-e89b-42d3-a456-426614174000.png',
      'Folder\u0000/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'Folder\u007f/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'Folder\u0085/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'C:/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'Folder/C:/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'file:attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'https://example.com/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      '//host/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'attachments/123E4567-e89b-42d3-a456-426614174000.png',
      'attachments/123e4567-e89b-42d3-a456-426614174000.PNG',
      'attachments/123e4567-e89b-42d3-a456-426614174000.svg',
      'Folder/attachments/123e4567-e89b-42d3-a456-426614174000.png/more',
    ]) {
      await expectLater(store.write(path, Uint8List(1)), throwsFormatException, reason: path);
      await expectLater(store.read(path), throwsFormatException, reason: path);
      await expectLater(store.readIfExists(path), throwsFormatException, reason: path);
      await expectLater(store.delete(path), throwsFormatException, reason: path);
    }
    expect(lookups, 0);
  });

  test('oversized writes reject before root lookup', () async {
    var lookups = 0;
    final store = PlatformAttachmentStore(
      rootLookup: () async {
        lookups++;
        throw StateError('unexpected root lookup');
      },
    );

    await expectLater(
      store.write(
        'attachments/123e4567-e89b-42d3-a456-426614174000.png',
        Uint8List(attachmentMaximumBytes + 1),
      ),
      throwsFormatException,
    );
    expect(lookups, 0);
  });

  test('writes and reads accept exactly the 10 MiB limit', () async {
    final bytes = Uint8List(attachmentMaximumBytes);
    final writeFake = _FakeFileSystem();
    final writeStore = PlatformAttachmentStore(
      rootLookup: () async => writeFake.rootHandle as web.FileSystemDirectoryHandle,
    );

    await writeStore.write('attachments/123e4567-e89b-42d3-a456-426614174000.png', bytes);
    expect(writeFake.writeCalls, 1);
    expect(writeFake.closeCalls, 1);

    final readFake = _FakeFileSystem(declaredSize: attachmentMaximumBytes, bytes: bytes);
    final readStore = PlatformAttachmentStore(
      rootLookup: () async => readFake.rootHandle as web.FileSystemDirectoryHandle,
    );
    expect(
      (await readStore.read('attachments/123e4567-e89b-42d3-a456-426614174000.png')).length,
      attachmentMaximumBytes,
    );
  });

  test('nested and root keys with the same leaf round-trip independently', () async {
    const leaf = '123e4567-e89b-42d3-a456-426614174000.png';
    const rootPath = 'attachments/$leaf';
    const nestedPath = 'School/attachments/$leaf';
    final rootBytes = Uint8List.fromList([1, 2, 3]);
    final nestedBytes = Uint8List.fromList([4, 5, 6]);
    final store = PlatformAttachmentStore();

    await store.write(rootPath, rootBytes);
    await store.write(nestedPath, nestedBytes);
    expect(await store.read(rootPath), rootBytes);
    expect(await store.read(nestedPath), nestedBytes);
    await store.delete(nestedPath);
    expect(await store.read(rootPath), rootBytes);
    await store.delete(rootPath);
  });

  test('reads and deletes do not create missing parent directories', () async {
    final directory = 'uncreated-${DateTime.now().microsecondsSinceEpoch}';
    final path = '$directory/Deep/attachments/123e4567-e89b-42d3-a456-426614174000.png';
    final store = PlatformAttachmentStore();
    final root = await web.window.navigator.storage.getDirectory().toDart;

    await expectLater(store.read(path), throwsA(isA<web.DOMException>()));
    expect(await store.readIfExists(path), isNull);
    await store.delete(path);
    await expectLater(
      root.getDirectoryHandle(directory).toDart,
      throwsA(isA<web.DOMException>()),
    );
  });

  test('optional reads and deletes tolerate only genuine absence', () async {
    final missing =
        'missing-${DateTime.now().microsecondsSinceEpoch}/attachments/123e4567-e89b-42d3-a456-426614174000.png';
    final store = PlatformAttachmentStore(
      rootLookup: () => Future<web.FileSystemDirectoryHandle>.error(
        web.DOMException('root denied', 'SecurityError'),
      ),
    );

    await expectLater(
      store.readIfExists(missing),
      throwsA(
        predicate((error) => error.isA<web.DOMException>() && (error! as web.DOMException).name == 'SecurityError'),
      ),
    );
    await expectLater(
      store.delete(missing),
      throwsA(
        predicate((error) => error.isA<web.DOMException>() && (error! as web.DOMException).name == 'SecurityError'),
      ),
    );
  });

  test('read checks declared size before buffering and actual length afterward', () async {
    var arrayBufferCalls = 0;
    final fake = _FakeFileSystem(declaredSize: attachmentMaximumBytes + 1, bytes: Uint8List(1));
    fake.file.setProperty(
      'arrayBuffer'.toJS,
      (() {
        arrayBufferCalls++;
        return fake.blob.arrayBuffer();
      }).toJS,
    );
    final store = PlatformAttachmentStore(rootLookup: () async => fake.rootHandle as web.FileSystemDirectoryHandle);

    await expectLater(
      store.read('attachments/123e4567-e89b-42d3-a456-426614174000.png'),
      throwsFormatException,
    );
    expect(arrayBufferCalls, 0);

    final oversizedBytes = Uint8List(attachmentMaximumBytes + 1);
    final actualSizeFake = _FakeFileSystem(declaredSize: 0, bytes: oversizedBytes);
    final actualSizeStore = PlatformAttachmentStore(
      rootLookup: () async => actualSizeFake.rootHandle as web.FileSystemDirectoryHandle,
    );
    await expectLater(
      actualSizeStore.read('attachments/123e4567-e89b-42d3-a456-426614174000.png'),
      throwsFormatException,
    );
  });

  for (final failedStep in ['write', 'close']) {
    test('failed $failedStep aborts best-effort and preserves original error', () async {
      final fake = _FakeFileSystem(failedWriteStep: failedStep);
      final store = PlatformAttachmentStore(rootLookup: () async => fake.rootHandle as web.FileSystemDirectoryHandle);

      await expectLater(
        store.write('Folder/attachments/123e4567-e89b-42d3-a456-426614174000.png', Uint8List(1)),
        throwsA(predicate((error) => error.toString().contains('$failedStep failed'))),
      );
      expect(fake.abortCalls, 1);
      expect(fake.createdDirectories, ['Folder', 'attachments']);
      expect(fake.directoryCreateFlags, [true, true]);
    });
  }
}

class _FakeFileSystem {
  _FakeFileSystem({int declaredSize = 1, Uint8List? bytes, this.failedWriteStep})
    : bytes = bytes ?? Uint8List.fromList([1]) {
    rootHandle = _object();
    directoryHandle = _object();
    fileHandle = _object();
    file = _object()..setProperty('size'.toJS, declaredSize.toJS);
    blob = web.Blob(<web.BlobPart>[this.bytes.toJS].toJS);
    writer = _object();

    final directory = directoryHandle as web.FileSystemDirectoryHandle;
    final fileSystemFileHandle = fileHandle as web.FileSystemFileHandle;
    rootHandle.setProperty(
      'getDirectoryHandle'.toJS,
      ((String name, web.FileSystemGetDirectoryOptions options) {
        createdDirectories.add(name);
        directoryCreateFlags.add(options.create);
        return _resolved(directory);
      }).toJS,
    );
    directoryHandle.setProperty(
      'getDirectoryHandle'.toJS,
      ((String name, web.FileSystemGetDirectoryOptions options) {
        createdDirectories.add(name);
        directoryCreateFlags.add(options.create);
        return _resolved(directory);
      }).toJS,
    );
    directoryHandle.setProperty(
      'getFileHandle'.toJS,
      ((String name, web.FileSystemGetFileOptions options) => _resolved(fileSystemFileHandle)).toJS,
    );
    fileHandle.setProperty(
      'getFile'.toJS,
      (() => _resolved(file as web.File)).toJS,
    );
    fileHandle.setProperty(
      'createWritable'.toJS,
      (() => _resolved(writer as web.FileSystemWritableFileStream)).toJS,
    );
    file.setProperty('arrayBuffer'.toJS, (() => blob.arrayBuffer()).toJS);
    writer.setProperty(
      'write'.toJS,
      ((JSAny _) {
        writeCalls++;
        if (failedWriteStep == 'write') return _rejected<JSAny?>(_failure('write failed'));
        return _resolved<JSAny?>(null);
      }).toJS,
    );
    writer.setProperty(
      'close'.toJS,
      (() {
        closeCalls++;
        if (failedWriteStep == 'close') return _rejected<JSAny?>(_failure('close failed'));
        return _resolved<JSAny?>(null);
      }).toJS,
    );
    writer.setProperty(
      'abort'.toJS,
      (() {
        abortCalls++;
        return _rejected<JSAny?>(_failure('abort failed'));
      }).toJS,
    );
  }

  final Uint8List bytes;
  final String? failedWriteStep;
  final createdDirectories = <String>[];
  final directoryCreateFlags = <bool>[];
  int abortCalls = 0;
  int writeCalls = 0;
  int closeCalls = 0;
  late final web.Blob blob;
  late final JSObject rootHandle;
  late final JSObject directoryHandle;
  late final JSObject fileHandle;
  late final JSObject file;
  late final JSObject writer;
}

JSObject _object() => web.EventTarget() as JSObject;

JSPromise<T> _resolved<T extends JSAny?>(T value) => JSPromise<T>(
  ((JSFunction resolve, JSFunction _) {
    resolve.callAsFunction(null, value);
  }).toJS,
);

JSPromise<T> _rejected<T extends JSAny?>(JSAny error) => JSPromise<T>(
  ((JSFunction _, JSFunction reject) {
    reject.callAsFunction(null, error);
  }).toJS,
);

web.DOMException _failure(String message) => web.DOMException(message, 'QuotaExceededError');
