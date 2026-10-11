// Verifies attachment storage behavior and text-image integration.
// Exercises attachment implementations through editor-facing contracts.

import 'dart:async';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/tools/media/media_tool.dart';
import 'package:elseplane/canvas/tools/text/text_block_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  for (final media in [false, true]) {
    for (final failure in [false, true]) {
      for (final dispose in [false, true]) {
        test(
          '${media ? 'media' : 'text'} cancels delayed reader ${failure ? 'failure' : 'text'} on ${dispose ? 'disposal' : 'restore'}',
          () async {
            final store = TestAttachmentStore();
            final text = media ? null : _model('original');
            final image = media
                ? MediaModel(MediaElementData(id: 'media', position: Offset.zero, width: 200, url: 'original'), store)
                : null;
            final reader = Completer<ClipboardReader>();
            final pending = media ? image!.paste(reader.future) : text!.paste(reader.future, store);
            if (dispose) {
              (text ?? image!).dispose();
            } else if (media) {
              image!.restoreData(image.data.copy());
            } else {
              text!.restoreData(text.data.copy());
            }
            if (failure) {
              reader.completeError(StateError('clipboard failed'));
            } else {
              reader.complete(_TextReader(Future.value('late')));
            }
            await pending;
            expect(media ? image!.data.url : text!.data.markdown, 'original');
            expect(store.files, isEmpty);
            if (!dispose) (text ?? image!).dispose();
          },
        );
      }
    }

    test('${media ? 'media' : 'text'} cancels clipboard content already being read', () async {
      final store = TestAttachmentStore();
      final text = media ? null : _model('original');
      final image = media
          ? MediaModel(MediaElementData(id: 'media', position: Offset.zero, width: 200, url: 'original'), store)
          : null;
      final value = Completer<String>();
      final reader = _TextReader(value.future);
      final pending = media ? image!.paste(Future.value(reader)) : text!.paste(Future.value(reader), store);
      await reader.started.future;
      if (media) {
        image!.invalidatePendingEdits();
      } else {
        text!.invalidatePendingEdits();
      }
      value.complete('late');
      await pending;
      expect(media ? image!.data.url : text!.data.markdown, 'original');
      (text ?? image!).dispose();
    });

    test('${media ? 'media' : 'text'} current reader failure still reports', () async {
      final store = TestAttachmentStore();
      final text = media ? null : _model('original');
      final image = media
          ? MediaModel(MediaElementData(id: 'media', position: Offset.zero, width: 200, url: 'original'), store)
          : null;
      final reader = Completer<ClipboardReader>();
      final pending = media ? image!.paste(reader.future) : text!.paste(reader.future, store);
      final check = expectLater(pending, throwsStateError);
      reader.completeError(StateError('clipboard failed'));
      await check;
      (text ?? image!).dispose();
    });
  }

  test('invalidation is silent and invalid restoration keeps pending edits', () {
    final model = _model('original');
    var notifications = 0;
    model.addListener(() => notifications++);
    model.documentChanges.addListener(() => notifications++);
    final generation = model.asyncEditGeneration;
    expect(() => model.restoreData(model.data.copy(id: 'other')), throwsArgumentError);
    expect(model.asyncEditGeneration, generation);
    model.invalidatePendingEdits();
    expect(model.asyncEditGeneration, generation + 1);
    expect(notifications, 0);
    model.dispose();
  });

  test(
    'pasted image is committed before its short reference is inserted',
    () async {
      final store = TestAttachmentStore();
      final model = _model('before after')
        ..controller.selection = const TextSelection(
          baseOffset: 7,
          extentOffset: 12,
        );
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);

      await model.insertPastedImage(bytes, 'png', store);

      final path = store.files.keys.single;
      expect(attachmentPathPattern.hasMatch(path), isTrue);
      expect(store.files[path], bytes);
      expect(model.node.markdown, 'before ![pasted image]($path)');
      expect(model.node.markdown, isNot(contains('base64')));
    },
  );

  test('oversized and failed image writes leave markdown unchanged', () async {
    final model = _model('unchanged');

    await expectLater(
      model.insertPastedImage(
        Uint8List(attachmentMaximumBytes + 1),
        'png',
        TestAttachmentStore(),
      ),
      throwsFormatException,
    );
    expect(model.node.markdown, 'unchanged');

    await expectLater(
      model.insertPastedImage(
        Uint8List.fromList(<int>[1]),
        'png',
        _FailingAttachmentStore(failWrites: true),
      ),
      throwsStateError,
    );
    expect(model.node.markdown, 'unchanged');
  });

  test('plain text paste replaces the current selection', () {
    final model = _model('before after')
      ..controller.selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 12,
      )
      ..insertPastedText('text');

    expect(model.node.markdown, 'before text');
    expect(
      model.controller.selection,
      const TextSelection.collapsed(offset: 11),
    );
  });

  test('attachment paths reject traversal and unsupported sources', () {
    for (final path in <String>[
      '../attachments/123.png',
      'attachments/not-a-uuid.png',
      'attachments/00000000-0000-4000-8000-000000000000.svg',
      'file:///attachments/00000000-0000-4000-8000-000000000000.png',
    ]) {
      expect(() => attachmentFileName(path), throwsFormatException);
    }
  });

  test('web attachment bytes survive a new store instance', () async {
    if (!kIsWeb) return;
    const path = 'attachments/00000000-0000-4000-8000-000000000000.webp';
    final bytes = Uint8List.fromList(<int>[4, 5, 6]);

    await createAttachmentStore().write(path, bytes);

    expect(await createAttachmentStore().read(path), bytes);
  });

  test('web deletion removes only its attachment and tolerates missing files', () async {
    const path = 'attachments/22222222-2222-4222-8222-222222222222.png';
    const otherPath = 'attachments/33333333-3333-4333-8333-333333333333.png';
    final store = createAttachmentStore();
    await store.write(path, onePixelPngBytes);
    await store.write(otherPath, onePixelPngBytes);

    await store.delete(path);
    expect(await store.readIfExists(path), isNull);
    expect(await store.read(otherPath), onePixelPngBytes);
    await store.delete(path);
    await store.delete(otherPath);
  });

  test('attachment deletion rejects invalid paths', () async {
    await expectLater(createAttachmentStore().delete('../attachments/image.png'), throwsFormatException);
  });

  test('optional attachment reads return present bytes or null', () async {
    const path = 'attachments/00000000-0000-4000-8000-000000000000.png';
    final bytes = Uint8List.fromList(<int>[7, 8, 9]);
    final store = TestAttachmentStore()..files[path] = bytes;

    expect(await store.readIfExists(path), bytes);
    expect(
      await store.readIfExists(
        'attachments/11111111-1111-4111-8111-111111111111.png',
      ),
      isNull,
    );
  });

  test('optional attachment reads still validate paths', () async {
    await expectLater(
      createAttachmentStore().readIfExists('not-an-attachment'),
      throwsFormatException,
    );
  });
}

TextBlockModel _model(String markdown) => TextBlockModel(
  TextElementData(
    id: 'text',
    position: Offset.zero,
    width: textNodeDefaultWidth,
    height: null,
    markdown: markdown,
    style: const TextNodeStyle(
      fontFamily: 'Inter',
      color: '#201C1A',
    ),
  ),
);

// ---------- Test doubles ----------

class _FailingAttachmentStore extends TestAttachmentStore {
  _FailingAttachmentStore({required this.failWrites});

  final bool failWrites;

  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (failWrites) throw StateError('write failed');
    await super.write(path, bytes);
  }
}

class _TextReader extends ClipboardReader {
  _TextReader(this.value) : super([]);

  final Future<String> value;
  final started = Completer<void>();

  @override
  bool canProvide(DataFormat format) => format == Formats.plainText;

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async {
    started.complete();
    return await value as T;
  }
}
