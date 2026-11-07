// Classifies supported public media links and loads bounded oEmbed metadata.
// Used by retained media resources; generic hosts never trigger preview requests.

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:elseplane/canvas/document/media_url.dart';
import 'package:http/http.dart' as http;

const Duration mediaLinkRequestTimeout = Duration(seconds: 5);
const int mediaLinkMaximumResponseBytes = 64 * 1024;

Size mediaLinkCardSize(String url, double width) => Size(
  width,
  width * (recognizeMediaLink(url) == null ? 112 / 480 : 3 / 4),
);

enum MediaLinkProvider { youtube, vimeo, spotify, soundCloud }

extension MediaLinkProviderName on MediaLinkProvider {
  String get displayName => switch (this) {
    MediaLinkProvider.youtube => 'YouTube',
    MediaLinkProvider.vimeo => 'Vimeo',
    MediaLinkProvider.spotify => 'Spotify',
    MediaLinkProvider.soundCloud => 'SoundCloud',
  };
}

class MediaLinkTarget {
  const MediaLinkTarget({required this.provider, required this.canonicalUrl, required this.endpoint});

  final MediaLinkProvider provider;
  final Uri canonicalUrl;
  final Uri endpoint;
}

class MediaLinkMetadata {
  const MediaLinkMetadata({
    required this.title,
    required this.providerName,
    this.authorName,
    this.thumbnailUri,
  });

  final String title;
  final String? authorName;
  final String providerName;
  final Uri? thumbnailUri;
}

class _ProviderConfig {
  const _ProviderConfig(this.provider, this.hosts, this.endpointHost, this.thumbnailHosts, this.thumbnailSuffixes);

  final MediaLinkProvider provider;
  final Set<String> hosts;
  final String endpointHost;
  final Set<String> thumbnailHosts;
  final Set<String> thumbnailSuffixes;

  bool allowsThumbnailHost(String host) =>
      thumbnailHosts.contains(host) || thumbnailSuffixes.any((suffix) => host.endsWith('.$suffix'));
}

const _providerConfigs = <_ProviderConfig>[
  _ProviderConfig(
    MediaLinkProvider.youtube,
    {'youtube.com', 'www.youtube.com', 'youtu.be'},
    'www.youtube.com',
    {'i.ytimg.com'},
    {},
  ),
  _ProviderConfig(MediaLinkProvider.vimeo, {'vimeo.com', 'www.vimeo.com'}, 'vimeo.com', {'i.vimeocdn.com'}, {}),
  _ProviderConfig(
    MediaLinkProvider.spotify,
    {'open.spotify.com'},
    'open.spotify.com',
    {'image-cdn-ak.spotifycdn.com'},
    {'spotifycdn.com'},
  ),
  _ProviderConfig(
    MediaLinkProvider.soundCloud,
    {'soundcloud.com', 'www.soundcloud.com'},
    'soundcloud.com',
    {'sndcdn.com'},
    {'sndcdn.com'},
  ),
];

MediaLinkTarget? recognizeMediaLink(String source) {
  if (!isSupportedMediaUrl(source)) return null;
  final uri = Uri.parse(source);
  if (uri.hasPort && uri.port != 443) return null;
  final config = _providerConfigs.where((value) => value.hosts.contains(uri.host)).firstOrNull;
  if (config == null || uri.path.contains('%')) return null;
  final parts = uri.pathSegments;
  String? resourcePath;
  switch (config.provider) {
    case MediaLinkProvider.youtube:
      if (uri.host == 'youtu.be' && parts.length == 1 && _youtubeId.hasMatch(parts.single)) {
        resourcePath = '/watch?v=${parts.single}';
      } else if (uri.path == '/watch' &&
          _youtubeId.hasMatch(uri.queryParameters['v'] ?? '') &&
          uri.queryParametersAll['v']?.length == 1) {
        resourcePath = '/watch?v=${uri.queryParameters['v']}';
      } else if (parts.length == 2 && parts.first == 'shorts' && _youtubeId.hasMatch(parts.last)) {
        resourcePath = '/watch?v=${parts.last}';
      }
    case MediaLinkProvider.vimeo:
      if (parts.length == 1 && _vimeoId.hasMatch(parts.single)) resourcePath = '/${parts.single}';
    case MediaLinkProvider.spotify:
      if (parts.length == 2 && _spotifyTypes.contains(parts.first) && _spotifyId.hasMatch(parts.last)) {
        resourcePath = '/${parts.first}/${parts.last}';
      }
    case MediaLinkProvider.soundCloud:
      if (parts.length == 2 && parts.every(_soundCloudSlug.hasMatch)) {
        resourcePath = '/${parts.join('/')}';
      } else if (parts.length == 3 && parts[1] == 'sets' && parts.every(_soundCloudSlug.hasMatch)) {
        resourcePath = '/${parts.join('/')}';
      }
  }
  if (resourcePath == null) return null;
  final canonicalHost = config.provider == MediaLinkProvider.youtube ? 'www.youtube.com' : config.endpointHost;
  final canonicalUrl = config.provider == MediaLinkProvider.youtube && resourcePath.startsWith('/watch?')
      ? Uri.https(canonicalHost, '/watch', {'v': resourcePath.substring('/watch?v='.length)})
      : Uri.https(canonicalHost, resourcePath);
  final endpoint = _oEmbedEndpoint(config, canonicalUrl);
  return MediaLinkTarget(provider: config.provider, canonicalUrl: canonicalUrl, endpoint: endpoint);
}

Uri? allowedMediaThumbnail(Uri? source, MediaLinkProvider provider) {
  if (source == null || !isSupportedMediaUrl(source.toString())) return null;
  if (source.hasPort && source.port != 443) return null;
  final config = _providerConfigs.firstWhere((value) => value.provider == provider);
  return config.allowsThumbnailHost(source.host) ? source : null;
}

MediaLinkMetadata? parseMediaLinkMetadata(String body, MediaLinkProvider provider) {
  if (utf8.encode(body).length > mediaLinkMaximumResponseBytes) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final title = _boundedString(decoded['title'], 512);
  final providerName = _boundedString(decoded['provider_name'], 128);
  final authorValue = decoded['author_name'];
  final authorName = authorValue == null ? null : _boundedString(authorValue, 256);
  if (title == null || providerName == null || (authorValue != null && authorName == null)) return null;
  final thumbnailValue = decoded['thumbnail_url'];
  final thumbnailUri = thumbnailValue is String && thumbnailValue.length <= 2048
      ? allowedMediaThumbnail(Uri.tryParse(thumbnailValue), provider)
      : null;
  return MediaLinkMetadata(
    title: title,
    providerName: providerName,
    authorName: authorName,
    thumbnailUri: thumbnailUri,
  );
}

class MediaLinkPreviewLoader {
  const MediaLinkPreviewLoader(this.client);

  final http.Client client;

  Future<MediaLinkMetadata?> load(MediaLinkTarget target) async {
    final abort = Completer<void>();
    try {
      return await _load(target, abort.future).timeout(
        mediaLinkRequestTimeout,
        onTimeout: () {
          abort.complete();
          throw TimeoutException('Future not completed', mediaLinkRequestTimeout);
        },
      );
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<MediaLinkMetadata?> _load(MediaLinkTarget target, Future<void> abort) async {
    final request = http.AbortableRequest('GET', target.endpoint, abortTrigger: abort);
    final response = await client.send(request);
    if (response.statusCode != 200) return null;
    final body = <int>[];
    await for (final chunk in response.stream) {
      if (body.length + chunk.length > mediaLinkMaximumResponseBytes) return null;
      body.addAll(chunk);
    }
    return parseMediaLinkMetadata(utf8.decode(body), target.provider);
  }
}

String? _boundedString(Object? value, int maximumLength) {
  if (value is! String || value.trim().isEmpty || value.length > maximumLength) return null;
  return value.trim();
}

Uri _oEmbedEndpoint(_ProviderConfig config, Uri canonical) => switch (config.provider) {
  MediaLinkProvider.youtube => Uri.https(config.endpointHost, '/oembed', {
    'url': canonical.toString(),
    'format': 'json',
  }),
  MediaLinkProvider.vimeo => Uri.https(config.endpointHost, '/api/oembed.json', {'url': canonical.toString()}),
  MediaLinkProvider.spotify => Uri.https(config.endpointHost, '/oembed', {'url': canonical.toString()}),
  MediaLinkProvider.soundCloud => Uri.https(config.endpointHost, '/oembed', {
    'format': 'json',
    'url': canonical.toString(),
  }),
};

final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _vimeoId = RegExp(r'^[0-9]{1,20}$');
final _spotifyId = RegExp(r'^[A-Za-z0-9]{22}$');
final _soundCloudSlug = RegExp(r'^[A-Za-z0-9_-]+$');
const Set<String> _spotifyTypes = {'track', 'album', 'playlist', 'artist', 'episode', 'show'};
