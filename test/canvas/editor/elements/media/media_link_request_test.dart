import 'dart:async';
import 'dart:convert';

import 'package:elseplane/canvas/editor/elements/media/media_link_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final target = recognizeMediaLink('https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl')!;

  test('aborts a request stalled before response headers at the deadline', () async {
    final sendStarted = Completer<void>();
    final aborted = Completer<void>();
    final response = Completer<http.StreamedResponse>();
    final client = _AbortAwareClient((request) {
      sendStarted.complete();
      unawaited(
        request.abortTrigger!.then((_) {
          aborted.complete();
          response.completeError(http.RequestAbortedException(request.url));
        }),
      );
      return response.future;
    });
    addTearDown(client.close);

    final loading = MediaLinkPreviewLoader(client).load(target);
    await sendStarted.future;
    await expectLater(loading, throwsA(isA<TimeoutException>()));
    await aborted.future;
  });

  test('aborts a response stalled while streaming its body at the deadline', () async {
    final aborted = Completer<void>();
    final body = StreamController<List<int>>();
    final client = _AbortAwareClient((request) {
      unawaited(
        request.abortTrigger!.then((_) {
          aborted.complete();
          body.addError(http.RequestAbortedException(request.url));
          unawaited(body.close());
        }),
      );
      return Future.value(http.StreamedResponse(body.stream, 200));
    });
    addTearDown(client.close);
    addTearDown(body.close);

    await expectLater(MediaLinkPreviewLoader(client).load(target), throwsA(isA<TimeoutException>()));
    await aborted.future;
  });

  test('keeps bounded parsing and cancels an oversized streamed body', () async {
    final success = _AbortAwareClient(
      (_) async => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'title': 'Track', 'provider_name': 'Spotify'}))),
        200,
      ),
    );
    addTearDown(success.close);
    expect((await MediaLinkPreviewLoader(success).load(target))?.title, 'Track');

    final bodyCanceled = Completer<void>();
    final requestAborted = Completer<void>();
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        body
          ..add(List.filled(mediaLinkMaximumResponseBytes, 0))
          ..add([0]);
        unawaited(body.close());
      },
      onCancel: bodyCanceled.complete,
    );
    final oversized = _AbortAwareClient((request) {
      unawaited(request.abortTrigger!.then((_) => requestAborted.complete()));
      return Future.value(http.StreamedResponse(body.stream, 200));
    });
    addTearDown(oversized.close);
    addTearDown(body.close);

    expect(await MediaLinkPreviewLoader(oversized).load(target), isNull);
    await bodyCanceled.future;
    await requestAborted.future;
  });
}

class _AbortAwareClient extends http.BaseClient {
  _AbortAwareClient(this.respond);

  final Future<http.StreamedResponse> Function(http.AbortableRequest request) respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => respond(request as http.AbortableRequest);

  @override
  void close() {}
}
