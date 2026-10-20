// Verifies font defaults, catalog browsing, and asynchronous block choices.
// Exercises the shared font service and the text settings panel in Chrome.

import 'dart:async';
import 'dart:convert';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/tools/text/text_block_model.dart';
import 'package:elseplane/canvas/tools/text/text_markdown_preview.dart';
import 'package:elseplane/canvas/tools/text/text_tool_settings.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:http/http.dart' as http;

import '../canvas/test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUpAll(() {
    // Chrome widget tests need an explicit asset manifest for the package loader.
    final manifest = const StandardMessageCodec().encodeMessage(<String, Object?>{})!;
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(base64Encode(Uint8List.sublistView(manifest)))));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async {
        assert(utf8.decode(Uint8List.sublistView(message!)) == 'AssetManifest.bin.json', 'Unexpected asset request');
        return ByteData.sublistView(bytes);
      },
    );
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
  });
  setUp(() => GoogleFontsLite.config.allowRuntimeFetching = false);
  tearDown(() => GoogleFontsLite.config.allowRuntimeFetching = true);

  testWidgets('both themes and default Markdown render with fetching disabled', (tester) async {
    await loadTextFont(defaultFontFamily);
    for (final theme in [starlessLightThemeData, starlessDarkThemeData]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: TextMarkdownPreview(
              source: '# Heading\n**bold** *italic* `code`\n\n\$x^2\$',
              style: const TextNodeStyle(fontFamily: defaultFontFamily, color: Color(0xff201C1A)),
              scrollController: null,
              onEdit: () {},
              onMove: (_) {},
              attachmentStore: TestAttachmentStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final styles = tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
      expect(styles.p!.fontFamily, defaultFontFamily);
      expect(styles.code!.fontFamily, defaultFontFamily);
      expect(styles.strong!.fontWeight, FontWeight.w600);
      expect(styles.em!.fontStyle, FontStyle.italic);
    }
  });

  testWidgets('unavailable saved fonts keep their name and render the bundled fallback', (tester) async {
    const family = 'Unavailable saved family';
    const style = TextNodeStyle(fontFamily: family);
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: TextMarkdownPreview(
            source: 'Saved text',
            style: style,
            scrollController: null,
            onEdit: () {},
            onMove: (_) {},
            attachmentStore: TestAttachmentStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!.p!.fontFamily, defaultFontFamily);
    final model = _model()..style = style;
    await _pumpSettings(tester, model, loadTextFont);
    expect(find.text(family), findsOneWidget);
    expect(model.style.fontFamily, family);
    expect(TextNodeStyle.fromJson(model.style.toJson()).fontFamily, family);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('catalog is searchable and builds only visible options without fetching', (tester) async {
    final model = _model();
    var loads = 0;
    await _pumpSettings(tester, model, (_) async {
      loads++;
    });
    final picker = tester.widget<SearchableSelect<String>>(find.byType(SearchableSelect<String>));
    expect(picker.options.length, GoogleFontsLite.fontsMap.length);
    expect(picker.preferredValues.first, model.style.fontFamily);
    await tester.tap(find.byKey(const ValueKey('searchable-select-trigger')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton).evaluate().length, lessThan(40));
    await tester.enterText(find.byKey(const ValueKey('searchable-select-search')), 'ABeeZee');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, 'ABeeZee'), findsOneWidget);
    expect(loads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('successful load commits once and preserves concurrent content and styling', (tester) async {
    final model = _model();
    final load = Completer<void>();
    var boundaries = 0;
    await _pumpSettings(tester, model, (_) => load.future, boundary: () => boundaries++);
    _choose(tester, 'ABeeZee');
    await tester.pump();
    expect(tester.widget<SearchableSelect<String>>(find.byType(SearchableSelect<String>)).onChanged, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(model.style.fontFamily, defaultFontFamily);
    model.controller.text = 'changed while loading';
    model.style = model.style.copyWith(color: const Color(0xffABCDEF), background: BlockBackgroundKind.glass);
    load.complete();
    await tester.pumpAndSettle();
    expect(model.style.fontFamily, 'ABeeZee');
    expect(model.style.color, const Color(0xffABCDEF));
    expect(model.style.background, BlockBackgroundKind.glass);
    expect(model.controller.text, 'changed while loading');
    expect(boundaries, 2);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('failed load retains the choice and shows an error', (tester) async {
    final model = _model();
    await _pumpSettings(tester, model, (_) async => throw StateError('offline'));
    _choose(tester, 'ABeeZee');
    await tester.pumpAndSettle();
    expect(model.style.fontFamily, defaultFontFamily);
    expect(find.text('Could not load font'), findsOneWidget);
    expect(tester.widget<SearchableSelect<String>>(find.byType(SearchableSelect<String>)).onChanged, isNotNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('deactivation permanently cancels a choice while the outgoing panel remains', (tester) async {
    final model = _model();
    final oldLoad = Completer<void>();
    final newLoad = Completer<void>();
    var boundaries = 0;
    await _pumpSettings(
      tester,
      model,
      (family) => family == 'ABeeZee' ? oldLoad.future : newLoad.future,
      boundary: () => boundaries++,
    );
    _choose(tester, 'ABeeZee');
    await tester.pump();
    model
      ..active = false
      ..active = true;
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.widget<SearchableSelect<String>>(find.byType(SearchableSelect<String>)).onChanged, isNotNull);
    _choose(tester, 'Abel');
    await tester.pump();
    oldLoad.complete();
    await tester.pump();
    expect(model.style.fontFamily, defaultFontFamily);
    expect(boundaries, 0);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    newLoad.complete();
    await tester.pumpAndSettle();
    expect(model.style.fontFamily, 'Abel');
    expect(boundaries, 2);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  for (final stale in ['deleted', 'replaced', 'changed choice', 'inactive']) {
    testWidgets('ignores completion after block is $stale', (tester) async {
      final model = _model();
      final replacement = _model();
      final load = Completer<void>();
      var boundaries = 0;
      await _pumpSettings(tester, model, (_) => load.future, boundary: () => boundaries++);
      _choose(tester, 'ABeeZee');
      await tester.pump();
      if (stale == 'deleted') {
        model.dispose();
      } else if (stale == 'replaced') {
        await _pumpSettings(tester, replacement, (_) async {});
      } else if (stale == 'inactive') {
        model.active = false;
      } else {
        model.style = model.style.copyWith(fontFamily: 'Inter');
      }
      load.complete();
      await tester.pumpAndSettle();
      expect(model.style.fontFamily, stale == 'changed choice' ? 'Inter' : defaultFontFamily);
      expect(boundaries, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      if (!model.disposed) model.dispose();
      replacement.dispose();
    });
  }

  test('catalog choices round-trip without changing the schema', () {
    for (final family in ['ABeeZee', 'Inter', defaultFontFamily]) {
      final style = TextNodeStyle(fontFamily: family, color: const Color(0xff201C1A));
      expect(TextNodeStyle.fromJson(style.toJson()).fontFamily, family);
    }
    expect(
      () => TextNodeStyle.fromJson({'fontFamily': '   ', 'color': '#201C1A', 'background': 'card'}),
      throwsFormatException,
    );
  });

  testWidgets('real downloads time out, release the queue, retry and render saved custom fonts', (tester) async {
    // Keep real service operations on one fake clock because the queue retains futures.
    {
      const saved = TextNodeStyle(fontFamily: 'ABeeZee', color: Color(0xff201C1A));
      await tester.pumpWidget(
        MaterialApp(
          theme: starlessLightThemeData,
          home: Scaffold(
            body: TextMarkdownPreview(
              source: 'saved **bold** *italic* `code`',
              style: saved,
              scrollController: null,
              onEdit: () {},
              onMove: (_) {},
              attachmentStore: TestAttachmentStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextMarkdownPreview>(find.byType(TextMarkdownPreview)).style.fontFamily, saved.fontFamily);
      final styles = tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
      expect(styles.p!.fontFamily, defaultFontFamily);
      expect(styles.strong!.fontFamily, defaultFontFamily);
      expect(styles.em!.fontFamily, defaultFontFamily);
      expect(styles.code!.fontFamily, defaultFontFamily);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    final files = <String, Uint8List>{};
    await tester.runAsync(() async {
      final client = http.Client();
      try {
        for (final (family, directory) in [('ABeeZee', 'abeezee'), ('Abel', 'abel')]) {
          for (final entry in GoogleFontsLite.fontsMap[family]!.entries) {
            final variant = entry.key.fontStyle == FontStyle.italic ? 'Italic' : 'Regular';
            final response = await client.get(Uri.base.resolve('/fixtures/fonts/$directory/$family-$variant.ttf'));
            expect(response.statusCode, 200);
            files[entry.value.url] = response.bodyBytes;
          }
        }
      } finally {
        client.close();
      }
    });
    final transport = _FontTransport(files);
    final previousClient = GoogleFontsLite.config.httpClient;
    GoogleFontsLite.config
      ..httpClient = transport
      ..allowRuntimeFetching = true;
    addTearDown(() {
      GoogleFontsLite.config.httpClient = previousClient;
      transport.close();
    });
    final model = _model();
    var boundaries = 0;
    await _pumpSettings(tester, model, loadTextFont, boundary: () => boundaries++);
    _choose(tester, 'ABeeZee');
    await tester.pump();
    await _waitForRequests(tester, transport, 2);
    final firstLoad = loadTextFont('ABeeZee');
    expect(loadTextFont('ABeeZee'), same(firstLoad));
    Object? failure;
    unawaited(
      firstLoad.catchError((Object error) {
        failure = error;
      }),
    );
    var queuedLoaded = false;
    unawaited(loadTextFont('Abel').then((_) => queuedLoaded = true));
    await tester.pump(const Duration(seconds: 9));
    expect(transport.requests, hasLength(2));
    expect(queuedLoaded, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await _waitForRequests(tester, transport, 3);
    await _pumpUntil(tester, () => queuedLoaded);
    await tester.pumpAndSettle();
    expect(failure.toString(), contains('TimeoutException'));
    expect(transport.aborted, hasLength(2));
    expect(model.style.fontFamily, defaultFontFamily);
    expect(boundaries, 0);
    expect(find.text('Could not load font'), findsOneWidget);
    expect(tester.widget<SearchableSelect<String>>(find.byType(SearchableSelect<String>)).onChanged, isNotNull);
    expect(queuedLoaded, isTrue);
    expect(textFontStyle('ABeeZee', const TextStyle()).fontFamily, defaultFontFamily);

    // A transport that completes after abortion must not publish a failed load.
    transport.finishLateHeaders();
    await tester.pump();
    expect(model.style.fontFamily, defaultFontFamily);
    expect(textFontStyle('ABeeZee', const TextStyle()).fontFamily, defaultFontFamily);

    transport.stall = _Stall.body;
    _choose(tester, 'ABeeZee');
    await tester.pump();
    await _waitForRequests(tester, transport, 5);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(transport.aborted, hasLength(4));
    expect(transport.canceledBodies, 2);
    expect(model.style.fontFamily, defaultFontFamily);
    expect(boundaries, 0);
    expect(find.text('Could not load font'), findsOneWidget);
    expect(tester.widget<SearchableSelect<String>>(find.byType(SearchableSelect<String>)).onChanged, isNotNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();

    transport.stall = _Stall.headers;
    final previewModel = _model();
    final saved = TextNodeStyle.fromJson({
      'fontFamily': 'ABeeZee',
      'color': '#201C1A',
      'background': 'card',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: Scaffold(
          body: Column(
            children: [
              TextMarkdownPreview(
                source: '# Heading\nBody **bold** *italic* `code`',
                style: saved,
                scrollController: null,
                onEdit: () {},
                onMove: (_) {},
                attachmentStore: TestAttachmentStore(),
              ),
              SizedBox(
                width: 280,
                child: TextToolSettings(
                  model: previewModel,
                  onChangeBoundary: () => boundaries++,
                  colorPickerExpanded: false,
                  onColorPickerExpandedChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _waitForRequests(tester, transport, 7);
    var styles = tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
    expect(styles.p!.fontFamily, defaultFontFamily);
    _choose(tester, 'ABeeZee');
    await tester.pump();
    previewModel
      ..active = false
      ..active = true;
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(transport.aborted, hasLength(4));
    var retryLoaded = false;
    unawaited(loadTextFont('ABeeZee').then((_) => retryLoaded = true));
    transport.finishLateHeaders();
    await _pumpUntil(tester, () => retryLoaded);
    await tester.pumpAndSettle();
    styles = tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
    expect(styles.p!.fontFamily, 'ABeeZee_regular');
    expect(styles.h1!.fontFamily, styles.p!.fontFamily);
    expect(styles.strong!.fontFamily, styles.p!.fontFamily);
    expect(styles.strong!.fontWeight, FontWeight.w600);
    expect(styles.em!.fontFamily, 'ABeeZee_italic');
    expect(styles.em!.fontStyle, FontStyle.italic);
    expect(styles.code!.fontFamily, defaultFontFamily);
    expect(previewModel.style.fontFamily, defaultFontFamily);
    expect(boundaries, 0);
    _choose(tester, 'Abel');
    previewModel.style = previewModel.style.copyWith(
      color: const Color(0xffABCDEF),
      background: BlockBackgroundKind.glass,
    );
    await tester.pumpAndSettle();
    expect(previewModel.style.fontFamily, 'Abel');
    expect(previewModel.style.color, const Color(0xffABCDEF));
    expect(previewModel.style.background, BlockBackgroundKind.glass);
    expect(boundaries, 2);
    for (final weight in [FontWeight.w400, FontWeight.w600]) {
      for (final style in FontStyle.values) {
        expect(textFontStyle('Abel', TextStyle(fontWeight: weight, fontStyle: style)).fontFamily, 'Abel_regular');
      }
    }
    final requestCount = transport.requests.length;
    await loadTextFont('ABeeZee');
    await loadTextFont('Abel');
    await loadTextFont(defaultFontFamily);
    expect(transport.requests, hasLength(requestCount));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    previewModel.dispose();
  });
}

// ---------- Helpers ----------

TextBlockModel _model() => TextBlockModel(
  TextElementData(
    id: 'text',
    position: Offset.zero,
    width: 420,
    height: 108,
    markdown: 'original',
    style: const TextNodeStyle(fontFamily: defaultFontFamily, color: Color(0xff201C1A)),
  ),
)..active = true;

Future<void> _pumpSettings(
  WidgetTester tester,
  TextBlockModel model,
  Future<void> Function(String) loader, {
  VoidCallback? boundary,
}) => tester.pumpWidget(
  MaterialApp(
    theme: starlessLightThemeData,
    home: Scaffold(
      body: SizedBox(
        width: 280,
        child: TextToolSettings(
          model: model,
          onChangeBoundary: boundary ?? () {},
          colorPickerExpanded: false,
          onColorPickerExpandedChanged: (_) {},
          loadFont: loader,
        ),
      ),
    ),
  ),
);

void _choose(WidgetTester tester, String family) =>
    tester.widget<SearchableSelect<String>>(find.byType(SearchableSelect<String>)).onChanged!(family);

// ---------- Real-loader transport ----------

enum _Stall { headers, body }

class _FontTransport extends http.BaseClient {
  _FontTransport(this.files);

  final Map<String, Uint8List> files;
  final requests = <http.BaseRequest>[];
  final aborted = <http.BaseRequest>[];
  final _headers = <(Completer<http.StreamedResponse>, http.BaseRequest)>[];
  _Stall stall = _Stall.headers;
  int canceledBodies = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final bytes = files[request.url.toString()]!;
    final abortable = request as http.AbortableRequest;
    if (request.url.toString() == GoogleFontsLite.fontsMap['Abel']!.values.single.url) {
      return http.StreamedResponse(Stream.value(bytes), 200);
    }
    if (stall == _Stall.headers) {
      final response = Completer<http.StreamedResponse>();
      _headers.add((response, request));
      unawaited(abortable.abortTrigger!.then((_) => aborted.add(request)));
      return await response.future;
    }
    final body = StreamController<List<int>>(onCancel: () => canceledBodies++);
    unawaited(
      abortable.abortTrigger!.then((_) {
        aborted.add(request);
        body.addError(http.RequestAbortedException(request.url));
        unawaited(body.close());
      }),
    );
    return http.StreamedResponse(body.stream, 200);
  }

  void finishLateHeaders() {
    for (final (response, request) in _headers) {
      response.complete(http.StreamedResponse(Stream.value(files[request.url.toString()]!), 200));
    }
    _headers.clear();
  }
}

Future<void> _waitForRequests(WidgetTester tester, _FontTransport transport, int count) async {
  await _pumpUntil(tester, () => transport.requests.length >= count);
  expect(transport.requests, hasLength(count));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() completed) async {
  for (var attempt = 0; attempt < 100 && !completed(); attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(completed(), isTrue);
}
