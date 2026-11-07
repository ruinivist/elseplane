// Verifies rich-card fallback keeps metadata and its reserved geometry.

import 'package:elseplane/canvas/editor/elements/media/media_link_card.dart';
import 'package:elseplane/canvas/editor/elements/media/media_link_preview.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('thumbnail failure keeps provider title and rich footprint', (tester) async {
    const url = 'https://www.youtube.com/watch?v=M7lc1UVf-VE&tracking=ignored#details';
    const title = 'A long video title that wraps across two lines without changing the provider card footprint';
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Center(
          child: MediaLinkCard(
            url: url,
            width: 480,
            target: recognizeMediaLink(url),
            metadata: const MediaLinkMetadata(
              title: title,
              providerName: 'YouTube',
              authorName: 'Creator',
            ),
            thumbnail: null,
            thumbnailFailed: true,
            selected: false,
          ),
        ),
      ),
    );

    expect(find.text(title), findsOneWidget);
    expect(tester.widget<Text>(find.text(title)).maxLines, 2);
    expect(find.text('YouTube · Creator'), findsOneWidget);
    expect(find.text('www.youtube.com'), findsOneWidget);
    expect(find.textContaining('tracking'), findsNothing);
    expect(find.textContaining('#details'), findsNothing);
    expect(tester.getSize(find.byType(MediaLinkCard)), const Size(480, 360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich card keeps hostname visible without overflowing at its minimum width', (tester) async {
    const url = 'https://www.youtube.com/watch?v=M7lc1UVf-VE&tracking=ignored#details';
    const title = 'A long title that is intentionally much wider than the narrow card';
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Center(
          child: MediaLinkCard(
            url: url,
            width: 200,
            target: recognizeMediaLink(url),
            metadata: const MediaLinkMetadata(title: title, providerName: 'YouTube', authorName: 'Creator'),
            thumbnail: null,
            thumbnailFailed: false,
            selected: false,
          ),
        ),
      ),
    );

    expect(find.text(title), findsOneWidget);
    expect(tester.widget<Text>(find.text(title)).maxLines, 1);
    expect(find.text('www.youtube.com'), findsOneWidget);
    expect(find.textContaining('tracking'), findsNothing);
    expect(find.textContaining('#details'), findsNothing);
    expect(tester.getSize(find.byType(MediaLinkCard)), const Size(200, 150));
    expect(tester.takeException(), isNull);
  });
}
