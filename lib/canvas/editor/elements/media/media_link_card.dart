// Renders generic and provider-backed media links with one shared card layout.
// Used by media elements for links, regardless of the source provider.

import 'package:elseplane/canvas/editor/elements/media/media_link_preview.dart';
import 'package:elseplane/canvas/editor/media_source.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/material.dart';

class MediaLinkCard extends StatelessWidget {
  const MediaLinkCard({
    required this.url,
    required this.width,
    required this.target,
    required this.metadata,
    required this.thumbnail,
    required this.thumbnailFailed,
    required this.selected,
    super.key,
  });

  final String url;
  final double width;
  final MediaLinkTarget? target;
  final MediaLinkMetadata? metadata;
  final ImageProvider<Object>? thumbnail;
  final bool thumbnailFailed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final size = mediaLinkCardSize(url, width);
    final rich = target != null;
    final compact = width < (rich ? 400 : 320);
    final tiny = width < 240;
    final thumbnailHeight = width * 9 / 16;
    final location = _location(url);
    return SizedBox.fromSize(
      size: size,
      child: Surface(
        selected: selected,
        raised: false,
        child: rich
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: thumbnailHeight,
                    child: ColoredBox(
                      color: colors.surfaceSubtle,
                      child: thumbnail != null && !thumbnailFailed
                          ? Image(
                              image: thumbnail!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => _thumbnailFallback(colors.textMuted),
                            )
                          : _thumbnailFallback(colors.textMuted),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: tiny ? 6 : 16, vertical: tiny ? 0 : 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            metadata?.title ?? location,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: (compact ? theme.typo.label.copyWith(fontSize: tiny ? 10 : 14) : theme.typo.title)
                                .copyWith(color: colors.textPrimary),
                          ),
                          SizedBox(height: compact ? 0 : 4),
                          Text(
                            _providerLine(metadata?.providerName ?? target!.provider.displayName, metadata),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typo.label.copyWith(
                              color: colors.textSecondary,
                              fontSize: tiny ? 8 : null,
                            ),
                          ),
                          SizedBox(height: compact ? 0 : 2),
                          Text(
                            _hostname(url),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typo.label.copyWith(
                              color: colors.textMuted,
                              fontSize: tiny ? 8 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: tiny ? 6 : 16, vertical: compact ? 0 : 12),
                child: Row(
                  children: [
                    Icon(Icons.link, color: colors.textSecondary, size: tiny ? 16 : 24),
                    SizedBox(width: tiny ? 8 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            compact ? location.replaceFirst('\n', ' ') : location.split('\n').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (tiny ? theme.typo.label.copyWith(fontSize: 10) : theme.typo.title).copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          if (!compact && location.contains('\n'))
                            Text(
                              location.split('\n').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typo.label.copyWith(color: colors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

Widget _thumbnailFallback(Color color) => Center(child: Icon(Icons.link, color: color, size: 28));

String _providerLine(String provider, MediaLinkMetadata? metadata) {
  final author = metadata?.authorName;
  return author == null || author.isEmpty ? provider : '$provider · $author';
}

String _hostname(String source) => resolveMediaUri(source)?.host ?? '';

String _location(String source) {
  final uri = resolveMediaUri(source);
  if (uri == null) return source.split(RegExp('[?#]')).first;
  final host = uri.host;
  var path = uri.path;
  if (path == '/') path = '';
  if (path.length > 48) path = '${path.substring(0, 45)}…';
  if (host.isEmpty) return path;
  return path.isEmpty ? host : '$host\n$path';
}
