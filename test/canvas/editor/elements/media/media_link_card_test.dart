// Verifies rich-card fallback keeps metadata and its reserved geometry.

import 'package:elseplane/canvas/editor/elements/media/media_link_card.dart';
import 'package:elseplane/canvas/editor/elements/media/media_link_preview.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../test_helpers.dart';

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
            thumbnail: MemoryImage(onePixelPngBytes),
            thumbnailFailed: true,
            selected: false,
          ),
        ),
      ),
    );

    expect(find.text(title), findsOneWidget);
    expect(tester.widget<Text>(find.text(title)).maxLines, 2);
    expect(find.text('YouTube · Creator'), findsNothing);
    expect(find.text('YouTube'), findsNothing);
    expect(find.text('Creator'), findsNothing);
    expect(find.byType(Image), findsNothing);
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

  testWidgets('rich card keeps title and hostname within the saved 120px width', (tester) async {
    const url = 'https://www.youtube.com/watch?v=M7lc1UVf-VE';
    const title = 'A saved narrow card still keeps its title readable';
    for (final theme in [starlessLightThemeData, starlessDarkThemeData]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: MediaLinkCard(
              url: url,
              width: 120,
              target: recognizeMediaLink(url),
              metadata: const MediaLinkMetadata(title: title, providerName: 'YouTube'),
              thumbnail: null,
              thumbnailFailed: false,
              selected: false,
            ),
          ),
        ),
      );

      final cardRect = tester.getRect(find.byType(MediaLinkCard));
      expect(cardRect.size, const Size(120, 90));
      expect(tester.getRect(find.text(title)).bottom, lessThanOrEqualTo(cardRect.bottom));
      expect(tester.getRect(find.text('www.youtube.com')).bottom, lessThanOrEqualTo(cardRect.bottom));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('generic card shows a resolved bare host and path without scheme or query', (tester) async {
    const source = '  example.com/articles/design?tracking=ignored#details  ';
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: const Center(
          child: MediaLinkCard(
            url: source,
            width: 480,
            target: null,
            metadata: null,
            thumbnail: null,
            thumbnailFailed: false,
            selected: false,
          ),
        ),
      ),
    );

    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('/articles/design'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.textContaining('tracking'), findsNothing);
    expect(find.textContaining('#details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generic card keeps its compact host and path at minimum width', (tester) async {
    const source = 'https://example.com/docs?tracking=ignored#details';
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: const Center(
          child: MediaLinkCard(
            url: source,
            width: 200,
            target: null,
            metadata: null,
            thumbnail: null,
            thumbnailFailed: false,
            selected: false,
          ),
        ),
      ),
    );
    expect(find.text('example.com · /docs'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
    final size = tester.getSize(find.byType(MediaLinkCard));
    expect(size.width, 200);
    expect(size.height, closeTo(200 / 6, 0.001));
    expect(find.textContaining('tracking'), findsNothing);
    expect(find.textContaining('#details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generic card renders within the saved 120px footprint', (tester) async {
    const source = 'https://example.com/docs';
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: const Center(
          child: MediaLinkCard(
            url: source,
            width: 120,
            target: null,
            metadata: null,
            thumbnail: null,
            thumbnailFailed: false,
            selected: false,
          ),
        ),
      ),
    );

    final cardRect = tester.getRect(find.byType(MediaLinkCard));
    final icon = find.byIcon(Icons.language);
    final tile = find.byWidgetPredicate((widget) => widget is SizedBox && widget.width == 16 && widget.height == 16);
    final tileRect = tester.getRect(tile);
    final iconRect = tester.getRect(icon);
    expect(cardRect.size, const Size(120, 20));
    expect(tileRect.size, const Size.square(16));
    expect(tileRect.top, greaterThanOrEqualTo(cardRect.top));
    expect(tileRect.bottom, lessThanOrEqualTo(cardRect.bottom));
    expect(iconRect.width, lessThanOrEqualTo(tileRect.width));
    expect(iconRect.height, lessThanOrEqualTo(tileRect.height));
  });

  testWidgets('rich card falls back to resolved host and path with a loaded thumbnail', (tester) async {
    const url = 'https://www.youtube.com/watch?v=M7lc1UVf-VE';
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Center(
          child: MediaLinkCard(
            url: url,
            width: 480,
            target: recognizeMediaLink(url),
            metadata: null,
            thumbnail: MemoryImage(onePixelPngBytes),
            thumbnailFailed: false,
            selected: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('www.youtube.com\n/watch'), findsOneWidget);
    expect(find.text('www.youtube.com'), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(tester.getSize(find.byType(MediaLinkCard)), const Size(480, 360));
  });
}
