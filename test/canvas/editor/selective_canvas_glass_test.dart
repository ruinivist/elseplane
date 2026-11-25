import 'dart:async';
import 'dart:typed_data';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/canvas_view.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_link_card.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_toolbar.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:material_ui/material_ui.dart';

import '../test_helpers.dart';

void main() {
  setUp(() => GoogleFontsLite.config.allowRuntimeFetching = false);
  tearDown(() => GoogleFontsLite.config.allowRuntimeFetching = true);

  testWidgets('glass follows card movement, saved order, and temporary lift', (tester) async {
    final session = _session([
      _text('text', const Offset(40, 90)),
      CodeElementData(
        id: 'code',
        position: const Offset(375, 90),
        size: codeBlockMinimumSize,
        language: CodeLanguage.dart,
        source: 'void main() {}',
        title: 'Example',
        showLineNumbers: false,
        background: BlockBackgroundKind.glass,
        autoArrange: false,
      ),
      MediaElementData(id: 'link', position: const Offset(450, 380), width: 230, url: 'https://example.com/'),
    ]);
    await _pumpCanvas(tester, session);

    final text = _note('text');
    final code = find.byType(CodeElementView);
    expect(_filters(tester, text), [false]);
    expect(_filters(tester, code), [false, false]);
    expect(_filters(tester, find.byType(CanvasToolbar)), [true]);
    expect(_filters(tester, find.byType(MediaLinkCard)), [true]);

    session.move(['code'], const Offset(-290, 0));
    await tester.pump();
    expect(_filters(tester, text), [false]);
    expect(_filters(tester, code), [true, true]);

    session
      ..setSelection(['text'])
      ..setActive('text');
    await tester.pumpAndSettle();
    expect(session.document.elements.map((element) => element.id), ['text', 'code', 'link']);
    expect(_filters(tester, text), [true]);
    expect(_filters(tester, code), [false, false]);

    session.setActive(null);
    await tester.pumpAndSettle();
    expect(_filters(tester, text), [false]);
    expect(_filters(tester, code), [true, true]);

    session.arrange(['code'], ['code', 'text', 'link']);
    await tester.pumpAndSettle();
    expect(_filters(tester, text), [true]);
    expect(_filters(tester, code), [false, false]);

    final camera = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final offset = camera.offset;
    final scale = camera.scale;
    camera
      ..onScaleStart(ScaleStartDetails())
      ..onScaleUpdate(ScaleUpdateDetails(focalPointDelta: const Offset(20, 30)))
      ..onScaleEnd(ScaleEndDetails())
      ..updateScalebyDelta(-0.6, focalPoint: Offset.zero);
    await tester.pumpAndSettle();
    expect(camera.offset, isNot(offset));
    expect(camera.scale, lessThan(scale));
    expect(_filters(tester, text), [true]);
    expect(_filters(tester, code), [false, false]);
  });

  testWidgets('the outgoing empty title follows the body when code loses its lift', (tester) async {
    final session = _session([
      CodeElementData(
        id: 'code',
        position: const Offset(40, 90),
        size: codeBlockMinimumSize,
        language: CodeLanguage.dart,
        source: 'void main() {}',
        title: '',
        showLineNumbers: false,
        background: BlockBackgroundKind.glass,
        autoArrange: false,
      ),
      _text('text', const Offset(90, 90)),
    ]);
    await _pumpCanvas(tester, session);
    final code = find.byType(CodeElementView);
    expect(_filters(tester, code), [false]);

    session.setActive('code');
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('code-title-input-tab-surface'));
    expect(_filters(tester, title), [true]);
    expect(_filters(tester, code), [true, true]);

    session.setActive(null);
    await tester.pump();
    expect(_filters(tester, title), [false]);
    expect(_filters(tester, code), [false, false]);
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(_filters(tester, code), [false]);
  });

  testWidgets('late local image geometry clears blur until the note moves over the photo', (tester) async {
    final attachments = _DelayedAttachment();
    final session = _session([
      MediaElementData(
        id: 'photo',
        position: const Offset(40, 90),
        width: 150,
        url: 'attachments/11111111-1111-4111-8111-111111111111.png',
      ),
      _text('text', const Offset(375, 90)),
    ]);
    await _pumpCanvas(tester, session, attachments: attachments);
    final photo = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    final text = _note('text');
    expect(photo.hasImage, isFalse);
    expect(_filters(tester, text), [true]);

    final document = session.document;
    attachments.bytes.complete(onePixelPngBytes);
    await pumpUntil(tester, () => photo.hasImage);
    expect(session.document, same(document));
    expect(_filters(tester, text), [false]);

    session.move(['text'], const Offset(-290, 0));
    await tester.pump();
    expect(_filters(tester, text), [true]);
  });

  testWidgets('an auto-height note keeps blur on itself and every later backdrop', (tester) async {
    final session = _session([
      _text('earlier', const Offset(40, 90)),
      _text('auto', const Offset(375, 90), height: null),
      _text('later', const Offset(375, 310)),
    ]);
    await _pumpCanvas(tester, session);
    expect(_filters(tester, _note('earlier')), [false]);
    expect(_filters(tester, _note('auto')), [true]);
    expect(_filters(tester, _note('later')), [true]);
  });

  testWidgets('changing the theme shadow updates which cards can skip blur', (tester) async {
    final session = _session([
      _text('lower', const Offset(40, 90)),
      _text('upper', const Offset(350, 90)),
    ]);
    final geo = starlessLightThemeData.extension<BTheme>()!.geo;
    final longerHalo = BGeo(
      radiusSmall: geo.radiusSmall,
      radiusMedium: geo.radiusMedium,
      radiusLarge: geo.radiusLarge,
      elevationLow: geo.elevationLow,
      elevationMedium: geo.elevationMedium,
      glassBlurSigma: geo.glassBlurSigma,
      glassShadow: const BoxShadow(blurRadius: 65, blurStyle: BlurStyle.outer),
    );
    final upper = _note('upper');
    await _pumpCanvas(tester, session);
    expect(_filters(tester, upper), [false]);

    await _pumpCanvas(tester, session, geometry: longerHalo);
    expect(_filters(tester, upper), [true]);

    await _pumpCanvas(tester, session);
    expect(_filters(tester, upper), [false]);
  });
}

EditorSession _session(List<CanvasElementData> elements) =>
    testSession(CanvasDocument(background: CanvasBackgroundKind.plain, elements: elements));

TextElementData _text(String id, Offset position, {double? height = 135}) => TextElementData(
  id: id,
  position: position,
  width: 220,
  height: height,
  markdown: 'A note',
  style: const TextNodeStyle(fontFamily: 'JetBrains Mono', background: BlockBackgroundKind.glass),
  autoArrange: false,
);

Finder _note(String id) => find.byWidgetPredicate((widget) => widget is TextElementView && widget.data.id == id);

List<bool> _filters(WidgetTester tester, Finder surface) => tester
    .widgetList<BackdropFilter>(find.descendant(of: surface, matching: find.byType(BackdropFilter)))
    .map((filter) => filter.enabled)
    .toList();

Future<void> _pumpCanvas(
  WidgetTester tester,
  EditorSession session, {
  TestAttachmentStore? attachments,
  BGeo? geometry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: starlessLightThemeData.copyWith(
        extensions: [
          starlessLightThemeData.extension<BTheme>()!.copyWith(geo: geometry, surfaceStyle: SurfaceStyle.glass),
        ],
      ),
      home: Scaffold(
        body: CanvasView(
          session: session,
          attachmentStore: attachments ?? TestAttachmentStore(),
          chromeBuilder: (_, _) => Align(
            alignment: Alignment.bottomCenter,
            child: CanvasToolbar(buttonsBuilder: ({required compact}) => const [Text('Tool')]),
          ),
          onOpenLibrary: (_) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _DelayedAttachment extends TestAttachmentStore {
  final bytes = Completer<Uint8List>();

  @override
  Future<Uint8List> read(String path) => bytes.future;
}
