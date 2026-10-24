// Verifies text editing, Markdown preview, styling, and interaction.
// Exercises text blocks through model and canvas widget flows.

import 'dart:math' as math;

import 'package:elseplane/app/workspace.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/canvas/tools/code/code_tool.dart';
import 'package:elseplane/canvas/tools/text/text_markdown_preview.dart';
import 'package:elseplane/canvas/tools/text/text_tool.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/main.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/preset_colors.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/color_picker.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../test_helpers.dart';

// ---------- Tests ----------

void main() {
  late UrlLauncherPlatform originalLauncher;
  late _FakeUrlLauncher launcher;

  setUp(() async {
    GoogleFontsLite.config.allowRuntimeFetching = false;
    SharedPreferencesAsyncWeb.registerWith(null);
    final preferences = SharedPreferencesAsync();
    await preferences.remove(PreferencesLibraryStore.libraryKey);
    originalLauncher = UrlLauncherPlatform.instance;
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    GoogleFontsLite.config.allowRuntimeFetching = true;
    UrlLauncherPlatform.instance = originalLauncher;
  });

  testWidgets('renderer owns initial and live rotation with rotated pointer targets', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_rendererDocument(rotation: math.pi / 2)));
    final block = find.byType(TextTool);
    final model = tester.widget<TextTool>(block).model;
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    expect(controller.getInfo(model.data.id).rotation, math.pi / 2);
    expect(controller.getInfo(model.data.id).gsPosition, model.canvasPosition);

    // The rotated left end lies above the unrotated layout rectangle.
    await tester.tapAt(const Offset(320, 190));
    await tester.pumpAndSettle();
    expect(model.active, isTrue);
    expect(model.editing, isTrue);
    expect(find.byKey(const ValueKey('text-block-handle')).hitTestable(), findsOneWidget);

    model.rotate(math.pi);
    expect(controller.getInfo(model.data.id).rotation, math.pi);
    await tester.pump();
    controller.updateScalebyDelta(-0.25, focalPoint: Offset.zero);
    await tester.pump();
    final before = model.canvasPosition;
    await tester.drag(
      find.byKey(const ValueKey('text-block-handle')),
      const Offset(30, 15),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(model.canvasPosition, before + const Offset(40, 20));
    expect(controller.getInfo(model.data.id).gsPosition, model.canvasPosition);
    expect(controller.childOrder, ['renderer-text']);
    await tester.pumpAndSettle();
  });

  testWidgets('auto-height measurements survive transient changes, rotation, and culling', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_rendererDocument(autoHeight: true)));
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    final controller = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    final measured = tester.getSize(find.byType(TextTool));
    expect(measured.height, greaterThan(model.canvasSize.height));
    expect(controller.getInfo(model.data.id).childSize, measured);

    model
      ..setSelected(value: true)
      ..setActive(value: true);
    expect(controller.getInfo(model.data.id).childSize, measured);
    model
      ..setActive(value: false)
      ..rotate(math.pi / 4);
    expect(controller.getInfo(model.data.id).childSize, measured);
    await tester.pump();
    controller.scrollBy(const Offset(10000, 10000));
    await tester.pumpAndSettle();
    expect(find.byType(TextTool), findsNothing);
    model
      ..setSelected(value: false)
      ..rotate(math.pi / 2)
      ..moveBy(const Offset(20, 10));
    expect(controller.getInfo(model.data.id).childSize, measured);
    expect(controller.getInfo(model.data.id).gsPosition, model.canvasPosition);
    expect(controller.getInfo(model.data.id).rotation, math.pi / 2);
    controller.scrollBy(const Offset(-10000, -10000));
    await tester.pumpAndSettle();
    expect(find.byType(TextTool), findsOneWidget);
    expect(controller.getInfo(model.data.id).childSize, measured);

    model.resize(measured, const Offset(20, 30));
    expect(controller.getInfo(model.data.id).childSize, model.canvasSize);
    await tester.pump();
    expect(tester.getSize(find.byType(TextTool)), model.canvasSize);
  });

  testWidgets('text places one focused source editor', (tester) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.pumpAndSettle();
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    final editor = find.byKey(const ValueKey('text-markdown-editor'));

    expect(find.byType(TextField), findsOneWidget);
    expect(model.active, isTrue);
    expect(model.editing, isTrue);
    expect(find.byType(ElementTransformControls), findsOneWidget);
    expect(
      find.byKey(const ValueKey('text-settings-panel')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('text-block-rotate-control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('text-block-delete-control')),
      findsOneWidget,
    );
    expect(model.focusNode.hasFocus, isTrue);
    await tester.enterText(editor, 'focused typing');
    await tester.pump();
    expect(model.node.markdown, 'focused typing');
    expect(
      tester.getTopLeft(editor),
      const Offset(120, 200),
    );
    expect(find.byKey(const ValueKey('text-block-handle')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('text-block-handle'))).dx,
      lessThan(tester.getTopLeft(editor).dx),
    );
    expect(
      find.byKey(const ValueKey('text-block-resize-handle')),
      findsOneWidget,
    );

    model.setSelected(value: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(model.focusNode.hasFocus, isFalse);
    expect(model.active, isFalse);
    expect(model.selected, isFalse);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('text-markdown-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('text-block-handle')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('text-block-resize-handle')).hitTestable(),
      findsNothing,
    );
    expect(find.byType(ElementTransformControls), findsOneWidget);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('text-block-resize-handle')),
      findsNothing,
    );
    expect(find.byType(ElementTransformControls), findsNothing);
  });

  testWidgets('text editor forwards arrow keys to native editing', (tester) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.pumpAndSettle();
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      'first line\nsecond line',
    );
    await tester.pump();
    expect(model.focusNode.hasFocus, isTrue);

    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ]) {
      expect(await tester.sendKeyEvent(key), isFalse, reason: '$key must reach the browser');
    }

    expect(model.editing, isTrue);
    expect(model.node.markdown, 'first line\nsecond line');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('text editor keeps native select and delete actions', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();
    await _placeCodeBlock(tester, const Offset(300, 200));
    final code = tester.widget<CodeTool>(find.byType(CodeTool)).model..setSelected(value: true);

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 200));
    await tester.pump();
    await tester.pump();
    final text = tester.widget<TextTool>(find.byType(TextTool)).model;
    final editor = find.byKey(const ValueKey('text-markdown-editor'));
    await tester.enterText(editor, 'native text');
    text.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.controller.text.length,
    );
    await tester.pump();
    expect(text.controller.selection.isCollapsed, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(find.byType(TextTool), findsOneWidget);
    expect(find.byType(CodeTool), findsOneWidget);
    expect(code.selected, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('code editor keeps native select and delete actions', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();
    await _placeCodeBlock(tester, const Offset(300, 200));
    final code = tester.widget<CodeTool>(find.byType(CodeTool)).model..setSelected(value: true);
    code.controller.text = 'native code';
    code.focusNode.requestFocus();
    await tester.pump();
    code.controller.selectAll();
    await tester.pump();
    expect(code.controller.isAllSelected, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(find.byType(CodeTool), findsOneWidget);
    expect(code.selected, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('deleting code keeps unrelated text editing open', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();
    await _placeCodeBlock(tester, const Offset(300, 200));
    final code = tester.widget<CodeTool>(find.byType(CodeTool)).model..setSelected(value: true);

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 200));
    await tester.pump();
    await tester.pump();
    final text = tester.widget<TextTool>(find.byType(TextTool)).model;
    expect(text.editing, isTrue);
    expect(find.byKey(const ValueKey('text-block-handle')), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CodeTool), findsNothing);
    expect(find.byType(TextTool), findsOneWidget);
    expect(text.editing, isTrue);
    expect(find.byKey(const ValueKey('text-block-handle')), findsOneWidget);
    expect(code.session.selectedIds, isNot(contains(code.data.id)));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('text blocks move from their handle', (tester) async {
    await _addTextBlock(tester, const Offset(120, 200));

    final textBlock = find.byType(TextTool);
    final handle = find.byKey(const ValueKey('text-block-handle'));
    final model = tester.widget<TextTool>(textBlock).model;
    final originalTopLeft = tester.getTopLeft(textBlock);
    final originalWidth = model.node.width;
    const delta = Offset(80, 60);

    await tester.drag(handle, delta, kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(tester.getTopLeft(textBlock), originalTopLeft + delta);
    expect(model.node.position, const Offset(200, 260));
    expect(model.node.width, originalWidth);
    expect(model.editing, isFalse);

    expect(find.byKey(const ValueKey('text-block-handle')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('text-block-resize-handle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('text-markdown-editor')), findsNothing);
    expect(find.byKey(const ValueKey('text-markdown-preview')), findsOneWidget);
  });

  testWidgets('text blocks delete from their controls', (tester) async {
    await _addTextBlock(tester, const Offset(120, 200));
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;

    await tester.tap(find.byKey(const ValueKey('text-block-delete-control')));
    await tester.pump();

    expect(model.editing, isFalse);
    expect(find.byType(TextTool), findsNothing);
  });

  testWidgets('inactive text blocks move without activating when zoomed', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    canvas.controller.updateScalebyDelta(1, focalPoint: Offset.zero);
    await tester.pump();

    final block = find.byType(TextTool);
    final model = tester.widget<TextTool>(block).model;
    final originalPosition = model.node.position;
    const delta = Offset(80, 60);

    final gesture = await tester.startGesture(
      tester.getTopLeft(
            find.byKey(const ValueKey('text-markdown-preview-surface')),
          ) +
          const Offset(32, 32),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(delta);
    await tester.pump();

    expect(canvas.controller.scale, 2);
    expect(model.node.position, originalPosition + delta / 2);
    expect(model.active, isFalse);
    expect(model.editing, isFalse);
    expect(model.focusNode.hasFocus, isFalse);
    expect(find.byKey(const ValueKey('text-markdown-preview')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(ElementTransformControls), findsNothing);
    expect(
      find.byKey(const ValueKey('text-block-resize-handle')),
      findsNothing,
    );

    await gesture.up();
    await tester.pump();

    expect(model.editing, isFalse);
    expect(find.byKey(const ValueKey('text-markdown-preview')), findsOneWidget);
    expect(find.byType(ElementTransformControls), findsNothing);
  });

  testWidgets('rotated preview movement stays in screen coordinates', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));

    final block = find.byType(TextTool);
    final model = tester.widget<TextTool>(block).model..rotate(math.pi / 2);
    await tester.pump();
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    final originalPosition = model.node.position;
    const delta = Offset(40, 0);
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('text-markdown-preview-surface')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(delta);
    await tester.pump();

    expect(model.node.position, originalPosition + delta);
    expect(model.editing, isFalse);

    await gesture.up();
    await tester.pump();
  });

  testWidgets(
    'text blocks rotate without clamping and keep controls coherent',
    (
      tester,
    ) async {
      await _addTextBlock(tester, const Offset(120, 200));

      final block = find.byType(TextTool);
      final model = tester.widget<TextTool>(block).model;
      final rotate = find.byKey(const ValueKey('text-block-rotate-control'));
      final center = tester.getCenter(block);
      final start = tester.getCenter(rotate);
      final radius = (start - center).distance;
      final startAngle = math.atan2(
        start.dy - center.dy,
        start.dx - center.dx,
      );
      final controlOffset = start - center;
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );

      for (var step = 1; step <= 3; step++) {
        await gesture.moveTo(
          center + Offset.fromDirection(startAngle + step * math.pi / 2, radius),
        );
        await tester.pump();
        if (step == 2) {
          expect(model.node.rotation.abs(), closeTo(math.pi, 0.01));
          final rotatedControl = tester.getCenter(rotate);
          expect(rotatedControl.dx, closeTo((center - controlOffset).dx, 1));
          expect(rotatedControl.dy, closeTo((center - controlOffset).dy, 1));
        }
      }
      await gesture.up();
      await tester.pump();

      expect(model.node.rotation.abs(), closeTo(math.pi * 1.5, 0.01));
      expect(model.editing, isFalse);
      expect(find.byKey(const ValueKey('text-markdown-preview')), findsOneWidget);
    },
  );

  testWidgets(
    'text resizing clamps and scrolls overflow',
    (tester) async {
      await _addTextBlock(
        tester,
        const Offset(120, 200),
        platform: TargetPlatform.linux,
      );
      final block = find.byType(TextTool);
      final model = tester.widget<TextTool>(block).model;
      final scrollbars = find.descendant(
        of: block,
        matching: find.byType(Scrollbar),
      );
      final position = model.node.position;
      final style = model.node.style;
      final originalHeight = tester.getSize(block).height;
      const source =
          'word word word word word word word word word word word word word '
          'word word word word word word word';

      await tester.enterText(
        find.byKey(const ValueKey('text-markdown-editor')),
        source,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      final originalWidth = model.node.width;
      expect(model.node.height, textNodeDefaultHeight);
      expect(scrollbars, findsOneWidget);
      final resizeHandle = find.byKey(
        const ValueKey('text-block-resize-handle'),
      );

      await tester.drag(resizeHandle, const Offset(80, 40));
      await tester.pump();

      expect(model.node.width, originalWidth + 80);
      expect(model.node.height, originalHeight + 40);
      expect(tester.getSize(block).width, originalWidth + 80);
      expect(tester.getSize(block).height, originalHeight + 40);
      expect(model.node.position, position);
      expect(model.node.markdown, source);
      expect(model.node.style, same(style));

      await tester.drag(resizeHandle, const Offset(-1000, -1000));
      await tester.pump();

      expect(model.node.width, textNodeMinimumWidth);
      expect(model.node.height, textNodeMinimumHeight);
      expect(tester.getSize(block).height, textNodeMinimumHeight);
      expect(model.scrollController.position.maxScrollExtent, greaterThan(0));
      expect(model.editing, isTrue);
      expect(scrollbars, findsOneWidget);
      expect(
        tester.widget<Scrollbar>(scrollbars).thumbVisibility,
        isTrue,
      );
      expect(model.node.position, position);
      expect(model.node.markdown, source);
      expect(model.node.style, same(style));

      await tester.tapAt(const Offset(700, 500));
      await tester.pump();
      expect(tester.getSize(block).height, textNodeMinimumHeight);
      expect(model.scrollController.position.maxScrollExtent, greaterThan(0));
      expect(model.editing, isFalse);
      expect(scrollbars, findsOneWidget);

      final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
      final canvasOffset = canvas.controller.offset;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(
          tester.getCenter(
            find.byKey(const ValueKey('text-markdown-preview-surface')),
          ),
        ),
      );
      model.scrollController.jumpTo(
        model.scrollController.position.maxScrollExtent,
      );
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, 20)),
      );
      await tester.pump();

      expect(canvas.controller.offset, canvasOffset);
    },
  );

  testWidgets('text resizing converts screen delta at canvas scale', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas));
    canvas.controller.updateScalebyDelta(1);
    await tester.pump();

    final originalSize = tester.getSize(find.byType(TextTool));
    final child = canvas.controller.widgetsWithScreenPositions().single;
    final blockSize = tester.getSize(find.byType(TextTool));
    final handleSize = tester.getSize(
      find.byKey(const ValueKey('text-block-resize-handle')),
    );
    final handlePosition =
        child.ssPosition +
        Offset(
          (model.node.width - handleSize.width / 2) * canvas.controller.scale,
          (blockSize.height - handleSize.height / 2) * canvas.controller.scale,
        );
    await tester.dragFrom(handlePosition, const Offset(80, 40));
    await tester.pump();

    expect(canvas.controller.scale, 2);
    expect(model.node.width, originalSize.width + 40);
    expect(model.node.height, originalSize.height + 20);
  });

  testWidgets('text source survives preview edit cycles', (tester) async {
    await _addTextBlock(tester, const Offset(120, 200));
    const source = '**exact** _source_\n\n- [x] task';

    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      source,
    );
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    expect(model.node.markdown, source);

    await tester.tapAt(const Offset(700, 500));
    await tester.pump();
    final preview = tester.widget<MarkdownBody>(
      find.byKey(const ValueKey('text-markdown-preview')),
    );
    expect(preview.data, source);

    await tester.tap(
      find.byKey(const ValueKey('text-markdown-preview-surface')),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(model.focusNode.hasFocus, isTrue);
    expect(model.editing, isTrue);
    expect(find.byKey(const ValueKey('text-markdown-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('text-block-handle')), findsOneWidget);
    expect(find.byType(ElementTransformControls), findsOneWidget);
    expect(model.controller.text, source);
    expect(model.node.markdown, source);

    const editedSource = '$source\n\nedited';
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      editedSource,
    );
    await tester.pump();
    expect(model.node.markdown, editedSource);

    await tester.tapAt(const Offset(700, 500));
    await tester.pump();
    expect(
      tester
          .widget<MarkdownBody>(
            find.byKey(const ValueKey('text-markdown-preview')),
          )
          .data,
      editedSource,
    );
  });

  testWidgets('text preview passes GFM, LaTeX, and semantic styles', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    const source = r'''
# Heading

**bold** and _italic_.

- [x] done

| A | B |
| - | - |
| 1 | 2 |

Inline $x^2$ and \(y_1\).

$$
a^2 + b^2 = c^2
$$

\[
x+y
\]''';

    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      source,
    );
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    expect(find.text('Heading', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    final equations = tester.widgetList<Math>(find.byType(Math)).toList();
    expect(equations.map((equation) => equation.mathStyle), [
      MathStyle.text,
      MathStyle.text,
      MathStyle.display,
      MathStyle.display,
    ]);
    expect(equations.every((equation) => equation.parseError == null), isTrue);

    final preview = tester.widget<MarkdownBody>(
      find.byKey(const ValueKey('text-markdown-preview')),
    );
    expect(preview.data, source);
  });

  testWidgets('Markdown uses theme heading and body roles while preserving custom colors', (tester) async {
    for (final theme in [starlessLightThemeData, starlessDarkThemeData]) {
      final colors = theme.extension<BTheme>()!.colors;
      for (final color in [null, const Color(0xffABCDEF)]) {
        final style = TextNodeStyle(fontFamily: defaultFontFamily, color: color);
        final saved = style.toJson();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: TextMarkdownPreview(
                source: '# Heading\nBody **bold** *italic* `code`\n\n> Quote\n\n- List\n\n\$x^2\$',
                style: style,
                scrollController: null,
                onEdit: () {},
                onMove: (_) {},
                attachmentStore: _FakeAttachmentStore(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final styles = tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
        final bodyColor = color ?? colors.textPrimary;
        final headingColor = color == null ? colors.textHeading : bodyColor;
        for (final heading in [styles.h1, styles.h2, styles.h3, styles.h4, styles.h5, styles.h6, styles.tableHead]) {
          expect(heading!.color, headingColor);
        }
        for (final body in [
          styles.p,
          styles.em,
          styles.strong,
          styles.blockquote,
          styles.listBullet,
          styles.tableBody,
        ]) {
          expect(body!.color, bodyColor);
        }
        expect(styles.code!.color, colors.textPrimary);
        expect(styles.a!.color, colors.accent);
        expect(tester.widget<Math>(find.byType(Math)).textStyle!.color, bodyColor);
        expect(style.toJson(), saved);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('Markdown code highlights labeled blocks and aliases in both themes', (tester) async {
    const examples = {
      'python': 'class Greeter:\n    def greet(self):\n        return "hello"',
      'py': 'return "alias"',
      'js': 'class Person {}\nfunction welcome() { return `hello \${42}`; }\nconst value = 42;',
      'ts': 'const value: number = 42;',
      'PYTHON': 'return "uppercase"',
    };
    const plain = {
      '': 'def unlabeled(): pass',
      'unknown': 'def unknown(): pass',
      'text': 'def plain(): pass',
    };
    final source = [
      for (final entry in {...examples, ...plain}.entries) '```${entry.key}\n${entry.value}\n```',
      '`inline`',
    ].join('\n\n');

    for (final theme in [starlessLightThemeData, starlessDarkThemeData]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TextMarkdownPreview(
                source: source,
                style: const TextNodeStyle(fontFamily: defaultFontFamily),
                scrollController: null,
                onEdit: () {},
                onMove: (_) {},
                attachmentStore: _FakeAttachmentStore(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final preview = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      final keywordColor = theme.extension<BTheme>()!.syntaxTheme['keyword']!.color;
      for (final code in examples.values) {
        final span = tester.widget<Text>(find.text(code)).textSpan!;
        var highlighted = false;
        span.visitChildren((child) {
          if (child is TextSpan && child.style?.color == keywordColor) highlighted = true;
          return true;
        });
        expect(highlighted, isTrue, reason: code);
        expect(span.toPlainText(), code);
      }
      for (final (language, token, role) in [
        ('python', 'Greeter', 'title'),
        ('python', 'greet', 'title'),
        ('python', 'class', 'keyword'),
        ('python', '"hello"', 'string'),
        ('js', 'Person', 'title'),
        ('js', 'welcome', 'title'),
        ('js', '42', 'number'),
        ('js', '`hello ', 'string'),
        ('js', r'${', 'subst'),
      ]) {
        final span = tester.widget<Text>(find.text(examples[language]!)).textSpan!;
        final tokens = <TextSpan>[];
        span.visitChildren((child) {
          if (child is TextSpan && child.text == token) tokens.add(child);
          return true;
        });
        expect(tokens, isNotEmpty, reason: '$language: $token');
        for (final tokenSpan in tokens) {
          expect(
            tokenSpan.style?.color,
            theme.extension<BTheme>()!.syntaxTheme[role]!.color,
            reason: '$language: $token',
          );
        }
      }
      for (final code in plain.values) {
        final span = tester.widget<Text>(find.text(code)).textSpan! as TextSpan;
        expect(span.children, isNull);
        expect(span.style, preview.styleSheet!.code);
      }
      expect(find.text('inline'), findsOneWidget);
      expect(preview.data, source);

      final highlighter = preview.syntaxHighlighter!;
      for (final oversized in ['a' * (1024 * 1024 + 1), 'a\n' * (2 * 1024 * 1024 + 1)]) {
        final span = highlighter.format(oversized, language: 'python');
        expect(span.children, isNull);
        expect(span.text, oversized);
      }
      expect(highlighter.format('', language: 'python').toPlainText(), isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('task checkboxes align with the first line in both themes', (tester) async {
    const tasks = ['Checked task', 'Unchecked task with enough words to wrap onto several lines'];
    for (final theme in [starlessLightThemeData, starlessDarkThemeData]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SizedBox(
              width: 220,
              child: TextMarkdownPreview(
                source: '- [x] ${tasks[0]}\n- [ ] ${tasks[1]}',
                style: const TextNodeStyle(fontFamily: defaultFontFamily, color: Color(0xff201C1A)),
                scrollController: null,
                onEdit: () {},
                onMove: (_) {},
                attachmentStore: _FakeAttachmentStore(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icons = [Icons.check_box, Icons.check_box_outline_blank];
      for (var i = 0; i < tasks.length; i++) {
        final icon = find.byIcon(icons[i]);
        final text = find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == tasks[i],
        );
        final paragraph = tester.renderObject<RenderParagraph>(text);
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: paragraph.size.width);
        final lines = painter.computeLineMetrics();
        if (i == 1) expect(lines.length, greaterThan(1));
        final firstLineCenter =
            tester.getTopLeft(text).dy + lines.first.baseline - lines.first.ascent + lines.first.height / 2;
        expect(tester.getCenter(icon).dy, closeTo(firstLineCenter, 1));
        expect(tester.getSize(icon).height, greaterThan(paragraph.text.style!.fontSize!));
        painter.dispose();
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('text preview keeps links safe and images restricted', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    const source = '''
![secure](https://example.com/image.png)

![unsafe](http://example.com/image.png)

![malformed](<https://[bad> "broken")

[safe](https://example.com) [unsafe link](javascript:alert(1))''';

    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      source,
    );
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    final preview = tester.widget<MarkdownBody>(
      find.byKey(const ValueKey('text-markdown-preview')),
    );
    final secureImage = preview.imageBuilder!(
      Uri.parse('https://example.com/image.png'),
      null,
      'secure',
    );
    final insecureImage = preview.imageBuilder!(
      Uri.parse('http://example.com/image.png'),
      null,
      'unsafe',
    );
    final networkImage = (secureImage as Padding).child! as Image;
    expect(networkImage.image, isA<NetworkImage>());
    expect(networkImage.width, double.infinity);
    expect(networkImage.height, isNull);
    expect(networkImage.fit, BoxFit.fitWidth);
    expect(insecureImage, isNot(isA<Image>()));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && (widget.properties.label == 'malformed' || widget.properties.label == 'unsafe'),
      ),
      findsNWidgets(2),
    );

    preview.onTapLink!('safe', 'https://example.com', '');
    await tester.pump();
    expect(launcher.launched, ['https://example.com']);
    expect(
      launcher.options.single.mode,
      PreferredLaunchMode.externalApplication,
    );

    preview.onTapLink!('unsafe link', 'javascript:alert(1)', '');
    await tester.pump();
    expect(launcher.launched, ['https://example.com']);
    expect(find.text('Could not open link'), findsOneWidget);
  });

  testWidgets('failed images use an alt-labelled broken-image fallback', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      '![failed](https://example.com/fails.png)',
    );
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    final preview = tester.widget<MarkdownBody>(
      find.byKey(const ValueKey('text-markdown-preview')),
    );
    final imagePadding = preview.imageBuilder!(
      Uri.parse('https://example.com/fails.png'),
      null,
      'failed',
    ) as Padding;
    final image = imagePadding.child! as Image;
    final fallback = image.errorBuilder!(
      tester.element(find.byKey(const ValueKey('text-markdown-preview'))),
      Exception('failed image'),
      StackTrace.current,
    );
    await tester.pumpWidget(MaterialApp(home: fallback));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'failed',
      ),
      findsOneWidget,
    );
  });

  testWidgets('stored attachment images resolve asynchronously', (
    tester,
  ) async {
    const path = 'attachments/00000000-0000-4000-8000-000000000000.png';
    final store = _FakeAttachmentStore()..files[path] = onePixelPngBytes;
    await _addTextBlock(
      tester,
      const Offset(120, 200),
      attachmentStore: store,
    );
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      '![stored]($path)',
    );

    await tester.tapAt(const Offset(700, 500));
    await tester.pump();
    await tester.pump();

    expect(store.readPaths, <String>[path]);
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isA<MemoryImage>(),
    );
  });

  testWidgets('missing attachments use the alt-labelled fallback', (
    tester,
  ) async {
    const path = 'attachments/00000000-0000-4000-8000-000000000000.webp';
    await _addTextBlock(
      tester,
      const Offset(120, 200),
      attachmentStore: _FakeAttachmentStore(),
    );
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      '![missing]($path)',
    );

    await tester.tapAt(const Offset(700, 500));
    await tester.pump();
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'missing',
      ),
      findsOneWidget,
    );
  });

  testWidgets('rendered link gestures do not enter text editing', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      '[safe](https://example.com) [unsafe](javascript:alert(1))',
    );
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    final links = find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan?.toPlainText() == 'safe unsafe',
    );
    expect(links, findsOneWidget);
    final linksTopLeft = tester.getTopLeft(links);
    final renderedLinks = tester.renderObject<RenderParagraph>(links);
    Offset linkPoint(int start, int end) =>
        linksTopLeft +
        renderedLinks
            .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: end),
            )
            .single
            .toRect()
            .center;

    await tester.tapAt(linkPoint(0, 4));
    await tester.pump();
    expect(launcher.launched, ['https://example.com']);
    expect(model.focusNode.hasFocus, isFalse);
    expect(find.byType(TextField), findsNothing);

    await tester.tapAt(linkPoint(5, 11));
    await tester.pump();
    expect(launcher.launched, ['https://example.com']);
    expect(model.focusNode.hasFocus, isFalse);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Could not open link'), findsOneWidget);
  });

  testWidgets('linked images keep their enclosing link gesture', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      '[![linked](https://example.com/image.png "title")](https://example.com/image)',
    );
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    final image = find.byType(Image);
    expect(image, findsOneWidget);
    final imageLink = tester.widget<GestureDetector>(
      find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.child is Padding && (widget.child! as Padding).child is Image,
      ),
    );
    imageLink.onTap!();
    await tester.pump();

    expect(launcher.launched, ['https://example.com/image']);
    expect(model.focusNode.hasFocus, isFalse);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('empty text preview has a clickable minimum area', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    final block = find.byType(TextTool);
    expect(tester.getSize(block).height, greaterThanOrEqualTo(52));

    await tester.tap(
      find.byKey(const ValueKey('text-markdown-preview-surface')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('text-markdown-editor')), findsOneWidget);
  });

  testWidgets(
    'text settings change model style without changing source',
    (
      tester,
    ) async {
      await _addTextBlock(tester, const Offset(120, 200));
      const source = '**styled source**';
      await tester.enterText(
        find.byKey(const ValueKey('text-markdown-editor')),
        source,
      );
      await tester.pumpAndSettle();

      final model = tester.widget<TextTool>(find.byType(TextTool)).model;
      expect(find.byType(ElementTransformControls), findsOneWidget);
      expect(
        find.byKey(const ValueKey('text-settings-panel')).hitTestable(),
        findsOneWidget,
      );

      model.setStyle(model.style.copyWith(fontFamily: 'ABeeZee'));
      await tester.pump();
      await tester.tap(_selectTrigger('text-font-select'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('searchable-select-search')), defaultFontFamily);
      await tester.pumpAndSettle();
      await tester.tap(find.text(defaultFontFamily).last);
      await tester.pumpAndSettle();

      expect(model.style.fontFamily, defaultFontFamily);
      expect(model.node.markdown, source);
      expect(model.active, isTrue);
      expect(model.editing, isFalse);
      expect(model.focusNode.hasFocus, isFalse);
      expect(
        find.byKey(const ValueKey('text-markdown-editor')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('text-markdown-preview')),
        findsOneWidget,
      );
      expect(find.byType(ElementTransformControls), findsOneWidget);

      expect(
        find.byKey(const ValueKey('color-preset-White')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('color-preset-Pink')),
        findsOneWidget,
      );

      final orangeSwatch = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Use Orange',
      );
      await tester.tap(orangeSwatch);
      await tester.pumpAndSettle();

      final orange = presetColors.singleWhere(
        (swatch) => swatch.label == 'Orange',
      );
      expect(model.style.color, orange.color);
      expect(model.node.markdown, source);
      expect(model.editing, isFalse);

      expect(model.style.background, BlockBackgroundKind.glass);
      final panelWidth = tester.getSize(find.byKey(const ValueKey('text-settings-panel'))).width;
      expect(tester.getSize(_selectTrigger('text-font-select')).width, panelWidth);
      expect(tester.getSize(_selectTrigger('text-background-select')).width, panelWidth);
      for (final background in BlockBackgroundKind.values) {
        await tester.tap(find.byKey(const ValueKey('text-markdown-preview-surface')));
        await tester.pumpAndSettle();
        expect(model.editing, isTrue);
        await _chooseBackground(tester, background);
        expect(model.style.background, background);
        expect(model.style.fontFamily, defaultFontFamily);
        expect(model.style.color, orange.color);
        expect(model.node.markdown, source);
        expect(model.active, isTrue);
        expect(model.editing, isFalse);
      }
    },
  );

  testWidgets('custom text color picker expands and follows active text', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.pumpAndSettle();
    final first = tester.widget<TextTool>(find.byType(TextTool)).model;
    final panel = find.byKey(const ValueKey('text-settings-panel'));
    final collapsedSize = tester.getSize(panel);

    await tester.tap(
      find.byKey(const ValueKey('color-picker-toggle')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    final animatingSize = tester.getSize(panel);
    await tester.pumpAndSettle();
    final expandedSize = tester.getSize(panel);

    expect(animatingSize.width, collapsedSize.width);
    expect(expandedSize.width, collapsedSize.width);
    expect(animatingSize.height, greaterThan(collapsedSize.height));
    expect(animatingSize.height, lessThan(expandedSize.height));

    final controlFinder = find.byType(ColorControl);
    final pickerFinder = find.byKey(const ValueKey('color-picker-custom'));
    final control = tester.widget<ColorControl>(controlFinder);
    expect(control.enableAlpha, isFalse);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: pickerFinder,
              matching: find.byType(TextField),
            ),
          )
          .maxLength,
      7,
    );

    control.onChanged(const Color(0xff123456));
    await tester.pump();
    expect(first.style.color, const Color(0xff123456));

    final second = await _placeTextBlock(tester, const Offset(480, 360));
    await tester.pumpAndSettle();
    expect(second.style.color, presetColors.first.color);
    expect(pickerFinder, findsOneWidget);
    expect(
      tester.widget<ColorControl>(controlFinder).color,
      presetColors.first.color,
    );

    await tester.tap(
      find.byKey(const ValueKey('color-picker-toggle')),
    );
    await tester.pumpAndSettle();
    expect(pickerFinder, findsNothing);
    expect(tester.getSize(panel), collapsedSize);
  });

  testWidgets('transparent background keeps editing and selection borders', (tester) async {
    await _addTextBlock(tester, const Offset(120, 200));
    await tester.pumpAndSettle();
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    final surface = find.byKey(const ValueKey('text-block-surface'));

    BorderSide border() => (tester.widget<Material>(surface).shape! as RoundedRectangleBorder).side;

    expect(model.style.background, BlockBackgroundKind.glass);
    await _chooseBackground(tester, BlockBackgroundKind.transparent);
    expect(model.style.background, BlockBackgroundKind.transparent);
    expect(model.active, isTrue);
    expect(model.editing, isFalse);
    expect(model.focusNode.hasFocus, isFalse);
    expect(border(), BorderSide.none);

    await tester.tap(find.byKey(const ValueKey('text-markdown-preview-surface')));
    await tester.pumpAndSettle();
    expect(model.editing, isTrue);
    expect(tester.widget<Material>(surface).type, MaterialType.transparency);
    expect(
      find.descendant(
        of: surface,
        matching: find.byType(PhysicalShape),
      ),
      findsNothing,
    );
    expect(border(), isNot(BorderSide.none));

    await tester.tapAt(const Offset(700, 500));
    await tester.pump();

    expect(model.editing, isFalse);
    expect(border(), BorderSide.none);

    model.setSelected(value: true);
    await tester.pump();

    expect(border(), isNot(BorderSide.none));
    expect(tester.widget<Material>(surface).type, MaterialType.canvas);
    expect(tester.widget<Material>(surface).color, isNotNull);
  });

  testWidgets('glass keeps a clipped backdrop in preview, editing, and selection', (tester) async {
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: starlessLightThemeData,
          darkTheme: starlessDarkThemeData,
          themeMode: themeMode,
          home: Workspace(
            libraryStore: TestLibraryStore(_rendererDocument()),
            attachmentStore: TestAttachmentStore(),
            projectFiles: TestProjectFiles(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final block = find.byType(TextTool);
      final model = tester.widget<TextTool>(block).model;
      final bounds = find.byKey(const ValueKey('text-block-surface'));
      final surface = find.descendant(of: bounds, matching: find.byType(Material)).first;
      final filter = find.descendant(of: block, matching: find.byType(BackdropFilter));

      void expectGlass() {
        expect(filter, findsOneWidget);
        final clip = find.ancestor(of: filter, matching: find.byType(ClipRRect)).first;
        expect(tester.getSize(clip), tester.getSize(surface));
        expect(tester.widget<BackdropFilter>(filter).child, tester.widget<Material>(surface));
        expect(tester.widget<BackdropFilter>(filter).backdropGroupKey, isNull);
        expect(tester.widget<Material>(surface).color!.a, inExclusiveRange(0, 1));
        expect(find.descendant(of: block, matching: find.byType(ImageFiltered)), findsNothing);
      }

      await tester.tap(find.byKey(const ValueKey('text-markdown-preview-surface')));
      await tester.pumpAndSettle();
      await _chooseBackground(tester, BlockBackgroundKind.glass);
      expect(model.active, isTrue);
      expect(model.editing, isFalse);
      expectGlass();

      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(model.active, isFalse);
      expectGlass();

      final previewColor = tester.widget<Material>(surface).color;
      model.setSelected(value: true);
      await tester.pump();
      expectGlass();
      expect(tester.widget<Material>(surface).color, isNot(previewColor));
      expect((tester.widget<Material>(surface).shape! as RoundedRectangleBorder).side, isNot(BorderSide.none));

      await tester.tap(find.byKey(const ValueKey('text-markdown-preview-surface')));
      await tester.pumpAndSettle();
      expect(model.editing, isTrue);
      expectGlass();
      expect(find.byKey(const ValueKey('text-markdown-editor')), findsOneWidget);

      for (final background in [BlockBackgroundKind.card, BlockBackgroundKind.transparent]) {
        await _chooseBackground(tester, background);
        expect(filter, findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('text editing is cleared by other blocks and empty canvas', (
    tester,
  ) async {
    await _addTextBlock(tester, const Offset(120, 200));
    final model = tester.widget<TextTool>(find.byType(TextTool)).model;
    expect(model.editing, isTrue);
    expect(find.byType(ElementTransformControls), findsOneWidget);

    await _placeCodeBlock(tester, const Offset(300, 200));
    await tester.pumpAndSettle();
    expect(model.editing, isFalse);
    expect(find.byKey(const ValueKey('code-block-handle')), findsOneWidget);

    await tester.tapAt(const Offset(24, 550));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(model.editing, isFalse);
    expect(find.byType(ElementTransformControls), findsNothing);
  });

  for (final picker in ['text-font-select', 'text-background-select']) {
    testWidgets('$picker owns Escape before the active canvas block', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_rendererDocument()));
      await tester.tap(find.byKey(const ValueKey('text-markdown-preview-surface')));
      await tester.pumpAndSettle();
      final model = tester.widget<TextTool>(find.byType(TextTool)).model;
      expect(model.active, isTrue);
      await tester.tap(_selectTrigger(picker));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(model.active, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(model.active, isFalse);
    });
  }

  testWidgets('editing a second text rebinds top-right settings', (
    tester,
  ) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();

    final first = await _placeTextBlock(tester, const Offset(120, 200));
    final second = await _placeTextBlock(tester, const Offset(480, 360));
    await tester.pumpAndSettle();
    first.setStyle(first.style.copyWith(fontFamily: 'Inter'));
    second.setStyle(second.style.copyWith(fontFamily: 'ABeeZee'));
    await tester.pump();

    tester
        .widget<SearchableSelect<String>>(find.byKey(const ValueKey('text-font-select')))
        .onChanged!
        .call(defaultFontFamily);
    await tester.pump();
    expect(second.style.fontFamily, defaultFontFamily);
    expect(first.style.fontFamily, 'Inter');
    await _chooseBackground(tester, BlockBackgroundKind.transparent);
    expect(second.style.background, BlockBackgroundKind.transparent);
    expect(first.style.background, BlockBackgroundKind.glass);

    await tester.tap(
      find.byKey(const ValueKey('text-markdown-preview-surface')).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('text-settings-panel')).hitTestable(),
      findsOneWidget,
    );
    tester
        .widget<SearchableSelect<String>>(find.byKey(const ValueKey('text-font-select')))
        .onChanged!
        .call(defaultFontFamily);
    await tester.pump();
    expect(first.style.fontFamily, defaultFontFamily);
    expect(second.style.fontFamily, defaultFontFamily);
    expect(
      tester.widget<Select<BlockBackgroundKind>>(find.byKey(const ValueKey('text-background-select'))).value,
      BlockBackgroundKind.glass,
    );
    await _chooseBackground(tester, BlockBackgroundKind.transparent);
    await _chooseBackground(tester, BlockBackgroundKind.card);
    expect(first.style.background, BlockBackgroundKind.card);
    expect(second.style.background, BlockBackgroundKind.transparent);
  });

  testWidgets('text nodes restore from the saved document', (tester) async {
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    final first = await _placeTextBlock(tester, const Offset(120, 200));
    const firstSource = '# first\n\n**exact**';
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      firstSource,
    );
    await tester.pump();

    final second = await _placeTextBlock(tester, const Offset(240, 300));
    const secondSource = '- second\n\n\$x^2\$';
    await tester.enterText(
      find.byKey(const ValueKey('text-markdown-editor')),
      secondSource,
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('text-block-handle')).hitTestable(),
      const Offset(60, 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('text-block-resize-handle')).hitTestable(),
      const Offset(40, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    tester
        .widget<SearchableSelect<String>>(find.byKey(const ValueKey('text-font-select')))
        .onChanged!
        .call(defaultFontFamily);
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Use Orange',
      ),
    );
    await tester.pump();

    await _chooseBackground(tester, BlockBackgroundKind.transparent);

    await tester.tapAt(const Offset(150, 220));
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await pumpPastSave(tester);

    final savedDocument = (await PreferencesLibraryStore().load())!.current.document!;
    final savedNodes = savedDocument.elements.whereType<TextElementData>().toList();
    expect(savedNodes, hasLength(2));
    final savedSecond = savedNodes.first;
    final savedFirst = savedNodes.last;
    expect(savedNodes.map((node) => node.id), [second.node.id, first.node.id]);
    expect(savedNodes.map((node) => node.markdown), [secondSource, firstSource]);
    expect(savedSecond.position, second.node.position);
    expect(savedSecond.width, second.node.width);
    expect(savedSecond.height, second.node.height);
    expect(savedSecond.style.fontFamily, defaultFontFamily);
    expect(savedFirst.style.background, BlockBackgroundKind.glass);
    expect(savedSecond.style.background, BlockBackgroundKind.transparent);
    expect(savedSecond.style.color, isNot(savedFirst.style.color));
    final canvas = tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
    expect(canvas.childOrder, [second.node.id, first.node.id]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    final restoredBlocks = tester.widgetList<TextTool>(find.byType(TextTool));
    final restoredNodes = restoredBlocks.map((block) => block.model.node);
    expect(restoredNodes.map((node) => node.toJson()), savedNodes.map((node) => node.toJson()));
    expect(
      tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller.childOrder,
      [second.node.id, first.node.id],
    );
    for (final block in restoredBlocks) {
      expect(block.model.editing, isFalse);
      expect(block.model.focusNode.hasFocus, isFalse);
    }
    expect(find.byType(ElementTransformControls), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('malformed saved libraries are preserved and reported', (
    tester,
  ) async {
    const invalid = '{"version":99,"currentId":"invalid","files":[]}';
    final preferences = SharedPreferencesAsync();
    await preferences.setString(PreferencesLibraryStore.libraryKey, invalid);

    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    expect(find.byType(TextTool), findsNothing);
    expect(find.text('Could not load saved canvas'), findsOneWidget);
    expect(await preferences.getString(PreferencesLibraryStore.libraryKey), invalid);

    await tester.tap(find.byKey(const ValueKey('toolbar-text')));
    await tester.pump();
    await tester.tapAt(const Offset(120, 200));
    await pumpPastSave(tester);
    expect(find.byType(TextTool), findsNothing);
    expect(await preferences.getString(PreferencesLibraryStore.libraryKey), invalid);
  });
}

// ---------- Test helpers ----------

Finder _selectTrigger(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byKey(ValueKey(key == 'text-font-select' ? 'searchable-select-trigger' : 'select-trigger')),
);

Future<void> _chooseBackground(WidgetTester tester, BlockBackgroundKind background) async {
  await tester.tap(_selectTrigger('text-background-select'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(MenuItemButton, switch (background) {
      BlockBackgroundKind.transparent => 'Transparent',
      BlockBackgroundKind.card => 'Card',
      BlockBackgroundKind.glass => 'Glass',
    }),
  );
  await tester.pumpAndSettle();
}

Future<void> _addTextBlock(
  WidgetTester tester,
  Offset position, {
  AttachmentStore? attachmentStore,
  TargetPlatform? platform,
}) async {
  if (platform == null) {
    await pumpElseplaneApp(tester, attachmentStore: attachmentStore);
  } else {
    await pumpCanvas(
      tester,
      PreferencesLibraryStore(),
      attachmentStore: attachmentStore,
      platform: platform,
    );
  }
  await _placeTextBlock(tester, position);
}

Future<TextBlockModel> _placeTextBlock(
  WidgetTester tester,
  Offset position,
) async {
  await tester.tap(find.byKey(const ValueKey('toolbar-text')));
  await tester.pump();
  await tester.tapAt(position);
  await tester.pump();
  await tester.pump();
  return tester.widget<TextTool>(find.byType(TextTool).last).model;
}

Future<void> _placeCodeBlock(WidgetTester tester, Offset position) async {
  await tester.tap(find.byKey(const ValueKey('toolbar-code')));
  await tester.pump();
  await tester.tapAt(position);
  await tester.pump();
}

// ---------- Test doubles ----------

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final launched = <String>[];
  final options = <LaunchOptions>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    this.options.add(options);
    return true;
  }
}

class _FakeAttachmentStore extends TestAttachmentStore {
  final readPaths = <String>[];

  @override
  Future<Uint8List> read(String path) async {
    readPaths.add(path);
    return await super.read(path);
  }
}

CanvasDocument _rendererDocument({double rotation = 0, bool autoHeight = false}) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    TextElementData(
      id: 'renderer-text',
      position: const Offset(200, 250),
      width: 240,
      height: autoHeight ? null : 80,
      rotation: rotation,
      markdown: autoHeight ? List.filled(8, 'Measured paragraph.').join('\n\n') : 'rotated text',
      style: const TextNodeStyle(fontFamily: defaultFontFamily, color: Color(0xff201C1A)),
    ),
  ],
);
