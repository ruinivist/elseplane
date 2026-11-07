// Previews the generic and provider-backed media link cards.

import 'package:elseplane/canvas/editor/elements/media/media_link_card.dart';
import 'package:elseplane/canvas/editor/elements/media/media_link_preview.dart';
import 'package:elseplane/ui/previews/theme_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

const _youtubeUrl = 'https://www.youtube.com/watch?v=M7lc1UVf-VE';

@Preview(name: 'Media rich link card', size: Size(520, 400), theme: previewTheme)
Widget mediaRichLinkCardPreview() => ColoredBox(
  color: Colors.transparent,
  child: Center(
    child: MediaLinkCard(
      url: _youtubeUrl,
      width: 480,
      target: recognizeMediaLink(_youtubeUrl),
      metadata: const MediaLinkMetadata(
        title: 'A video worth watching',
        providerName: 'YouTube',
        authorName: 'Elseplane',
      ),
      thumbnail: null,
      thumbnailFailed: false,
      selected: false,
    ),
  ),
);

@Preview(name: 'Media generic link card', size: Size(520, 160), theme: previewTheme)
Widget mediaGenericLinkCardPreview() => const Center(
  child: MediaLinkCard(
    url: 'https://example.com/articles/canvas-design?tracking=ignored',
    width: 480,
    target: null,
    metadata: null,
    thumbnail: null,
    thumbnailFailed: false,
    selected: false,
  ),
);
