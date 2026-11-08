// Verifies safe provider matching, bounded metadata parsing, and retained loads.

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/elements/media/media_link_preview.dart';
import 'package:elseplane/canvas/editor/media_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../test_helpers.dart';

void main() {
  const youtube = 'https://www.youtube.com/watch?v=M7lc1UVf-VE';
  const soundCloud = 'https://soundcloud.com/forss/flickermood';

  test('recognizes the approved public resource shapes and canonicalizes requests', () {
    final urls = {
      'https://www.youtube.com/watch?v=M7lc1UVf-VE&list=ignored#clip': (
        'www.youtube.com',
        'https://www.youtube.com/watch?v=M7lc1UVf-VE',
      ),
      'https://youtu.be/M7lc1UVf-VE?si=ignored': ('www.youtube.com', 'https://www.youtube.com/watch?v=M7lc1UVf-VE'),
      'https://www.youtube.com/shorts/M7lc1UVf-VE?feature=ignored': (
        'www.youtube.com',
        'https://www.youtube.com/watch?v=M7lc1UVf-VE',
      ),
      'https://vimeo.com/76979871?share=copy': ('vimeo.com', 'https://vimeo.com/76979871'),
      'https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl?si=ignored': (
        'open.spotify.com',
        'https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl',
      ),
      soundCloud: ('soundcloud.com', soundCloud),
      'https://soundcloud.com/forss/sets/favorites?utm_source=ignored': (
        'soundcloud.com',
        'https://soundcloud.com/forss/sets/favorites',
      ),
    };
    for (final entry in urls.entries) {
      final target = recognizeMediaLink(entry.key);
      expect(target, isNotNull, reason: entry.key);
      expect(target!.endpoint.host, entry.value.$1);
      expect(target.canonicalUrl.toString(), entry.value.$2);
      expect(target.endpoint.queryParameters['url'], entry.value.$2);
    }
    expect(
      recognizeMediaLink(youtube)!.endpoint.toString(),
      'https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DM7lc1UVf-VE&format=json',
    );
    expect(
      recognizeMediaLink('https://vimeo.com/76979871')!.endpoint.path,
      '/api/oembed.json',
    );
    expect(recognizeMediaLink('https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl')!.endpoint.path, '/oembed');
    expect(recognizeMediaLink(soundCloud)!.endpoint.queryParameters['format'], 'json');
  });

  test('resolves bare provider sources to canonical HTTPS preview endpoints', () {
    final target = recognizeMediaLink('  youtu.be/M7lc1UVf-VE?si=ignored  ');
    expect(target!.canonicalUrl.toString(), 'https://www.youtube.com/watch?v=M7lc1UVf-VE');
    expect(target.endpoint.host, 'www.youtube.com');
  });

  test('use-time resolution trims and defaults bare addresses without accepting other schemes', () {
    expect(resolveMediaUri('  example.com/articles/design  ').toString(), 'https://example.com/articles/design');
    expect(resolveMediaUri('example.com:8080/path')!.port, 8080);
    expect(resolveMediaUri('localhost:8080')!.host, 'localhost');
    expect(resolveMediaUri('127.0.0.1:8080')!.host, '127.0.0.1');
    expect(resolveMediaUri('[::1]:8080')!.port, 8080);
    expect(resolveMediaUri('http://example.com/path')!.scheme, 'http');
    expect(resolveMediaUri('javascript:alert(1)'), isNull);
    expect(resolveMediaUri('javascript:8080'), isNull);
    expect(resolveMediaUri('https://example.com:999999999999999999999/path'), isNull);
  });

  test('rejects malformed provider shapes, spoofed hosts, credentials, and insecure schemes', () {
    for (final url in [
      'http://youtu.be/M7lc1UVf-VE',
      'https://user:secret@youtu.be/M7lc1UVf-VE',
      'https://youtu.be.attacker.test/M7lc1UVf-VE',
      'https://youtube.com.attacker.test/watch?v=M7lc1UVf-VE',
      'https://www.youtube.com/watch?v=short',
      'https://www.youtube.com/watch?v=M7lc1UVf-VE&v=otherid',
      'https://vimeo.com/not-numeric',
      'https://open.spotify.com/track/not-a-public-id',
      'https://soundcloud.com/user/sets/playlist/extra',
      'https://www.youtube.com:444/watch?v=M7lc1UVf-VE',
      'https://www.youtube.com:0/watch?v=M7lc1UVf-VE',
      'https://bad host.example/path',
      ' https://example.com/path ',
    ]) {
      expect(recognizeMediaLink(url), isNull, reason: url);
    }
    expect(recognizeMediaLink('$youtube&${List.filled(2048, 'x').join()}'), isNull);
  });

  test('infers display from attachments and resolved URL path suffixes', () {
    expect(isImageMediaSource('attachments/11111111-1111-4111-8111-111111111111.png'), isTrue);
    expect(isLinkMediaSource('attachments/11111111-1111-4111-8111-111111111111.png'), isFalse);
    expect(isImageMediaSource('https://example.com/IMAGE.JPEG?download=1'), isTrue);
    expect(isImageMediaSource('example.com/IMAGE.JPEG?download=1'), isTrue);
    expect(isLinkMediaSource('https://example.com/IMAGE.JPEG?download=1'), isFalse);
    expect(isImageMediaSource('https://example.com/articles/one?source=share'), isFalse);
    expect(isLinkMediaSource('https://example.com/articles/one?source=share'), isTrue);
    expect(isImageMediaSource(youtube), isFalse);
    expect(isLinkMediaSource(youtube), isTrue);
    expect(isImageMediaSource('http://example.com/image.png'), isFalse);
    expect(isLinkMediaSource('http://example.com/image.png'), isTrue);

    final legacy = MediaElementData.fromJson({
      'id': 'media',
      'type': 'media',
      'position': {'x': 0.0, 'y': 0.0},
      'width': 480.0,
      'url': youtube,
    });
    expect(legacy.url, youtube);
    expect(legacy.toJson(), isNot(contains('kind')));
    expect(MediaElementData.fromJson(legacy.toJson()), legacy);

    final invalidLegacy = MediaElementData.fromJson({
      'id': 'invalid',
      'type': 'media',
      'position': {'x': 0.0, 'y': 0.0},
      'width': 480.0,
      'url': 'javascript:alert(1)',
    });
    expect(invalidLegacy.url, 'javascript:alert(1)');
    expect(isImageMediaSource(invalidLegacy.url), isFalse);
    expect(isLinkMediaSource(invalidLegacy.url), isFalse);
  });

  test('URL changes update inferred presentation as one undoable media edit', () {
    const imageUrl = 'https://example.com/image.png';
    final media = MediaElementData(id: 'media', position: Offset.zero, width: 480, url: imageUrl);
    final resources = testMediaModel(media, TestAttachmentStore());
    addTearDown(resources.dispose);
    resources.session.setMediaUrl(media.id, 'https://example.com/articles/design');
    resources.session.finishOperation();
    expect(resources.isLink, isTrue);
    resources.session.undo();
    expect(resources.data.url, imageUrl);
    expect(resources.isLink, isFalse);
  });

  test('provider metadata remains source-keyed across geometry undo', () async {
    final media = MediaElementData(
      id: 'media',
      position: Offset.zero,
      width: 480,
      url: youtube,
    );
    var requestCount = 0;
    final client = MockClient((_) async {
      requestCount++;
      return _metadataResponse('Retained');
    });
    final resources = testMediaModel(media, TestAttachmentStore(), previewClient: client);
    addTearDown(resources.dispose);
    addTearDown(client.close);

    resources.loadLinkPreview();
    await Future<void>.delayed(Duration.zero);
    expect(resources.linkMetadata?.title, 'Retained');
    expect(requestCount, 1);
    resources.session.move([media.id], const Offset(12, 0));
    resources.session.finishOperation();
    resources.session.undo();
    resources.loadLinkPreview();
    await Future<void>.delayed(Duration.zero);
    expect(resources.linkMetadata?.title, 'Retained');
    expect(requestCount, 1);
  });

  test('parses bounded text and only provider-approved HTTPS thumbnails', () {
    final metadata = parseMediaLinkMetadata(
      jsonEncode({
        'title': '  Video title  ',
        'provider_name': 'YouTube',
        'author_name': 'Creator',
        'thumbnail_url': 'https://i.ytimg.com/vi/M7lc1UVf-VE/480x360.jpg',
        'html': '<iframe src="untrusted"></iframe>',
      }),
      MediaLinkProvider.youtube,
    );
    expect(metadata?.title, 'Video title');
    expect(metadata?.providerName, 'YouTube');
    expect(metadata?.authorName, 'Creator');
    expect(metadata?.thumbnailUri?.host, 'i.ytimg.com');

    final withoutAuthor = parseMediaLinkMetadata(
      '{"title":"Title","provider_name":"Vimeo","thumbnail_url":"https://i.vimeocdn.com/image.jpg"}',
      MediaLinkProvider.vimeo,
    );
    expect(withoutAuthor?.authorName, isNull);
    expect(withoutAuthor?.thumbnailUri?.host, 'i.vimeocdn.com');

    final unsafeThumbnail = parseMediaLinkMetadata(
      '{"title":"Title","provider_name":"YouTube","thumbnail_url":"https://i.ytimg.com.attacker.test/image.jpg"}',
      MediaLinkProvider.youtube,
    );
    expect(unsafeThumbnail?.title, 'Title');
    expect(unsafeThumbnail?.thumbnailUri, isNull);
    expect(
      parseMediaLinkMetadata(
        '{"title":"Title","provider_name":"YouTube","thumbnail_url":"https://user:secret@i.ytimg.com/image.jpg"}',
        MediaLinkProvider.youtube,
      )?.thumbnailUri,
      isNull,
    );
    expect(
      parseMediaLinkMetadata(
        '{"title":"Title","provider_name":"YouTube","thumbnail_url":"http://i.ytimg.com/image.jpg"}',
        MediaLinkProvider.youtube,
      )?.thumbnailUri,
      isNull,
    );
    expect(
      allowedMediaThumbnail(
        Uri.tryParse('https://i.ytimg.com:999999999999999999999/image.jpg'),
        MediaLinkProvider.youtube,
      ),
      isNull,
    );
    expect(
      parseMediaLinkMetadata(
        '{"title":"Title","provider_name":"Spotify","thumbnail_url":"https://sub.spotifycdn.com/image.jpg"}',
        MediaLinkProvider.spotify,
      )?.thumbnailUri?.host,
      'sub.spotifycdn.com',
    );
    expect(
      parseMediaLinkMetadata(
        '{"title":"Title","provider_name":"SoundCloud","thumbnail_url":"https://i1.sndcdn.com/image.jpg"}',
        MediaLinkProvider.soundCloud,
      )?.thumbnailUri?.host,
      'i1.sndcdn.com',
    );
    expect(
      parseMediaLinkMetadata(
        '{"title":"Title","provider_name":"SoundCloud","thumbnail_url":"https://sndcdn.com.attacker.test/image.jpg"}',
        MediaLinkProvider.soundCloud,
      )?.thumbnailUri,
      isNull,
    );

    expect(parseMediaLinkMetadata('<html>preview</html>', MediaLinkProvider.youtube), isNull);
    expect(parseMediaLinkMetadata('{"title":3,"provider_name":"YouTube"}', MediaLinkProvider.youtube), isNull);
    expect(
      parseMediaLinkMetadata(
        jsonEncode({'title': List.filled(513, 'x').join(), 'provider_name': 'YouTube'}),
        MediaLinkProvider.youtube,
      ),
      isNull,
    );
    expect(
      parseMediaLinkMetadata(
        List.filled(mediaLinkMaximumResponseBytes + 1, 'x').join(),
        MediaLinkProvider.youtube,
      ),
      isNull,
    );
  });

  test('uses one bounded oEmbed request and falls back on HTTP or body failures', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({'title': 'Track', 'provider_name': 'Spotify'}),
        200,
      );
    });
    addTearDown(client.close);
    final target = recognizeMediaLink('https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl')!;
    final result = await MediaLinkPreviewLoader(client).load(target);
    expect(result?.title, 'Track');
    expect(requests, hasLength(1));
    expect(requests.single.url, target.endpoint);

    final oversized = MockClient(
      (_) async => http.Response(List.filled(mediaLinkMaximumResponseBytes + 1, 'x').join(), 200),
    );
    addTearDown(oversized.close);
    expect(await MediaLinkPreviewLoader(oversized).load(target), isNull);
    final failed = MockClient((_) async => http.Response('unavailable', 503));
    addTearDown(failed.close);
    expect(await MediaLinkPreviewLoader(failed).load(target), isNull);
  });

  test('times out requests after the five-second deadline', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    addTearDown(client.close);
    await expectLater(
      MediaLinkPreviewLoader(client).load(recognizeMediaLink(youtube)!),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('retained results ignore stale URL responses and removal', () async {
    final responses = <String, Completer<http.Response>>{};
    final calls = <String>[];
    final client = MockClient((request) {
      final url = request.url.queryParameters['url']!;
      calls.add(url);
      return (responses[url] = Completer<http.Response>()).future;
    });
    final first = MediaElementData(id: 'media', position: Offset.zero, width: 480, url: youtube);
    final resources = testMediaModel(first, TestAttachmentStore(), previewClient: client);
    addTearDown(resources.dispose);
    addTearDown(client.close);

    resources
      ..loadLinkPreview()
      ..loadLinkPreview();
    await Future<void>.delayed(Duration.zero);
    expect(calls, [youtube]);
    const secondUrl = 'https://youtu.be/dQw4w9WgXcQ?tracking=ignored';
    resources.session.setMediaUrl(first.id, secondUrl);
    resources.loadLinkPreview();
    await Future<void>.delayed(Duration.zero);
    expect(calls, [youtube, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ']);

    responses[youtube]!.complete(_metadataResponse('Stale'));
    responses['https://www.youtube.com/watch?v=dQw4w9WgXcQ']!.complete(_metadataResponse('Current'));
    await Future<void>.delayed(Duration.zero);
    expect(resources.linkMetadata?.title, 'Current');

    const removedUrl = 'https://www.youtube.com/shorts/9bZkp7q19f0';
    resources.session.setMediaUrl(first.id, removedUrl);
    resources.loadLinkPreview();
    await Future<void>.delayed(Duration.zero);
    resources.session.remove([first.id]);
    responses['https://www.youtube.com/watch?v=9bZkp7q19f0']!.complete(_metadataResponse('Removed'));
    await Future<void>.delayed(Duration.zero);
    expect(resources.linkMetadata, isNull);
    expect(resources.attached, isFalse);
  });

  test('document replacement rejects a delayed metadata response', () async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    final media = MediaElementData(id: 'media', position: Offset.zero, width: 480, url: youtube);
    final resources = testMediaModel(media, TestAttachmentStore(), previewClient: client);
    addTearDown(resources.dispose);
    addTearDown(client.close);

    resources.loadLinkPreview();
    await Future<void>.delayed(Duration.zero);
    resources.session.endLifetime();
    response.complete(_metadataResponse('Late document result'));
    await Future<void>.delayed(Duration.zero);
    expect(resources.linkMetadata, isNull);
    expect(resources.attached, isFalse);
  });

  test('generic hosts never request metadata and card geometry is stable', () async {
    final richLink = MediaElementData(id: 'rich', position: Offset.zero, width: 480, url: youtube);
    final generic = richLink.copyWith(url: 'https://example.com/extensionless?secret=hidden');
    var requestCount = 0;
    final client = MockClient((_) async {
      requestCount++;
      return _metadataResponse('Never requested');
    });
    final resources = testMediaModel(generic, TestAttachmentStore(), previewClient: client);
    addTearDown(resources.dispose);
    addTearDown(client.close);
    resources.loadLinkPreview();
    await Future<void>.delayed(Duration.zero);

    expect(mediaLinkCardSize(richLink.url, richLink.width), const Size(480, 360));
    expect(mediaLinkCardSize(generic.url, generic.width), const Size(480, 112));
    expect(recognizeMediaLink(generic.url), isNull);
    expect(requestCount, 0);
  });
}

http.Response _metadataResponse(String title) => http.Response(
  jsonEncode({'title': title, 'provider_name': 'YouTube'}),
  200,
);
