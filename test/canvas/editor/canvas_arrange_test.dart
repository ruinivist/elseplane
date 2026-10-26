// Verifies object Arrange menus, shortcuts, persistence, and history.
// Exercises ordering through the canvas rather than reproducing the library algorithm.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:elseplane/app/app.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/element_resources.dart';
import 'package:elseplane/canvas/editor/elements/arrow/arrow_element_view.dart';
import 'package:elseplane/canvas/editor/elements/code/code_element_view.dart';
import 'package:elseplane/canvas/editor/elements/media/media_element_view.dart';
import 'package:elseplane/canvas/editor/elements/pen/pen_element_view.dart';
import 'package:elseplane/canvas/editor/elements/shape/shape_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_element_view.dart';
import 'package:elseplane/canvas/editor/elements/text/text_markdown_editor.dart';
import 'package:elseplane/canvas/editor/widgets/element_transform_controls.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/library/canvas_library.dart';
import 'package:elseplane/library/library_store.dart';
import 'package:elseplane/library/widgets/canvas_file_picker.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/glass_surface.dart';
import 'package:elseplane/ui/common/labeled_switch.dart';
import 'package:elseplane/ui/common/menu_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';

import '../test_helpers.dart';

// ---------- Tests ----------

void main() {
  setUp(() => SharedPreferencesAsyncWeb.registerWith(null));

  for (final kind in ['text', 'code', 'title']) {
    for (final device in [PointerDeviceKind.mouse, if (kind != 'title') PointerDeviceKind.touch]) {
      testWidgets('Auto active $kind $device tap promotes without restarting editing', (tester) async {
        final document = _autoDocument(kind).withElements(
          (elements) => elements[elements.length - 1] = elements[elements.length - 1].copyWith(autoArrange: true),
        );
        final store = TestLibraryStore(document);
        await pumpCanvas(tester, store);
        await tester.tapAt(_autoHitPoint(tester, kind));
        await tester.pumpAndSettle();
        final text = kind == 'text' ? tester.widget<TextElementView>(find.byType(TextElementView)).resources : null;
        final code = kind == 'text' ? null : tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
        final focus = text?.focusNode ?? code!.focusNode;
        await _promoteOther(tester);
        var focusLosses = 0;
        void trackFocus() {
          if (!focus.hasFocus) focusLosses++;
        }

        focus.addListener(trackFocus);
        final point = _activeEditorHitPoint(tester, kind);
        await tester.tapAt(point, kind: device);
        await tester.pumpAndSettle();
        focus.removeListener(trackFocus);
        expect(_canvas(tester).childOrder, ['other', 'editor']);
        expect(text?.active ?? code!.active, isTrue);
        expect(text?.controller.text ?? code!.controller.text, 'contents');
        if (kind != 'title') {
          expect(focus.hasFocus, isTrue);
          expect(focusLosses, 0);
        }
        if (text != null) expect(text.editing, isTrue);
        await tester.tapAt(point, kind: device);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await _shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(_canvas(tester).childOrder, ['editor', 'other']);
        await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
        expect(_canvas(tester).childOrder, ['other', 'editor']);
        await pumpPastSave(tester);
        await tester.pumpWidget(const SizedBox());
        await pumpCanvas(tester, TestLibraryStore(store.persisted));
        expect(_canvas(tester).childOrder, ['other', 'editor']);
      });
    }

    testWidgets('Auto $kind content edit promotes with content in one undo step', (tester) async {
      final document = _autoDocument(kind).withElements(
        (elements) => elements[elements.length - 1] = elements[elements.length - 1].copyWith(autoArrange: true),
      );
      await pumpCanvas(tester, TestLibraryStore(document));
      await tester.tapAt(_autoHitPoint(tester, kind));
      await tester.pumpAndSettle();
      final text = kind == 'text' ? tester.widget<TextElementView>(find.byType(TextElementView)).resources : null;
      final code = kind == 'text' ? null : tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
      await _promoteOther(tester);
      if (text != null) {
        text.controller.selection = const TextSelection.collapsed(offset: 0);
      } else {
        code!.controller.cancelSelection();
      }
      expect(_canvas(tester).childOrder, ['editor', 'other']);
      if (text != null) {
        text.insertPastedText('pasted ');
      } else if (kind == 'title') {
        code!.titleController.text = 'Edited title';
      } else {
        code!.controller.text = 'edited source';
      }
      await tester.pump();
      expect(_canvas(tester).childOrder, ['other', 'editor']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(_canvas(tester).childOrder, ['editor', 'other']);
      expect(text?.controller.text ?? code!.controller.text, 'contents');
      if (kind == 'title') expect(code!.titleController.text, 'Title');
      await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(_canvas(tester).childOrder, ['other', 'editor']);
      expect(
        kind == 'title' ? code!.titleController.text : text?.controller.text ?? code!.controller.text,
        switch (kind) {
          'text' => 'pasted contents',
          'title' => 'Edited title',
          _ => 'edited source',
        },
      );
    });
  }

  for (final kind in ['text', 'code']) {
    testWidgets('Auto active $kind canceled taps and touch navigation preserve saved order', (tester) async {
      final document = _autoDocument(kind).withElements(
        (elements) => elements[elements.length - 1] = elements[elements.length - 1].copyWith(autoArrange: true),
      );
      await pumpCanvas(tester, TestLibraryStore(document));
      await tester.tapAt(_autoHitPoint(tester, kind));
      await tester.pumpAndSettle();
      await _promoteOther(tester);
      final point = _activeEditorHitPoint(tester, kind);
      final canceled = await tester.startGesture(point, pointer: 1);
      await canceled.cancel();
      await tester.pump();
      expect(_canvas(tester).childOrder, ['editor', 'other']);
      final first = await tester.startGesture(point, pointer: 2);
      final second = await tester.startGesture(const Offset(700, 500), pointer: 3);
      await second.up();
      await first.up();
      await tester.pumpAndSettle();
      expect(_canvas(tester).childOrder, ['editor', 'other']);
    });
  }

  testWidgets('canceled image paste leaves content, stacking, and history unchanged after editing ends', (
    tester,
  ) async {
    final document = _autoDocument('text').withElements(
      (elements) => elements[elements.length - 1] = elements[elements.length - 1].copyWith(autoArrange: true),
    );
    final attachments = _DelayedAttachmentStore();
    await pumpCanvas(tester, TestLibraryStore(document), attachmentStore: attachments);
    await tester.tapAt(_autoHitPoint(tester, 'text'));
    await tester.pumpAndSettle();
    final model = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
    model.controller.selection = const TextSelection.collapsed(offset: 0);
    final paste = model.insertPastedImage(onePixelPngBytes, 'png', attachments);
    await _promoteOther(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(model.editing, isFalse);
    attachments.resume.complete();
    await paste;
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, ['editor', 'other']);
    expect(model.controller.text, 'contents');
    expect(attachments.files, isEmpty);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_canvas(tester).childOrder, ['other', 'editor']);
    expect(model.controller.text, 'contents');
    await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(_canvas(tester).childOrder, ['editor', 'other']);
    expect(model.controller.text, 'contents');
  });

  for (final image in [false, true]) {
    for (final auto in [true, false]) {
      testWidgets(
        'Markdown ${image ? 'image' : 'text'} link respects Auto $auto without editing or bypassing validation',
        (
          tester,
        ) async {
          var document = _autoDocument('text');
          document = document.withElements(
            (elements) => elements[0] = (elements.first as TextElementData).copyWith(
              autoArrange: auto,
              markdown: image
                  ? '[![linked](http://example.com/image.png)](javascript:alert(1))'
                  : '[link](javascript:alert(1))',
            ),
          );
          await pumpCanvas(tester, TestLibraryStore(document));
          await tester.pumpAndSettle();
          final Offset point;
          if (image) {
            point = tester.getCenter(find.byIcon(Icons.broken_image_outlined));
          } else {
            final link = find.byWidgetPredicate((widget) => widget is Text && widget.textSpan?.toPlainText() == 'link');
            final paragraph = tester.renderObject<RenderParagraph>(link);
            point =
                tester.getTopLeft(link) +
                paragraph
                    .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 4))
                    .single
                    .toRect()
                    .center;
          }
          await tester.tapAt(point);
          await tester.pumpAndSettle();
          expect(_canvas(tester).childOrder, auto ? ['other', 'editor'] : ['editor', 'other']);
          final model = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
          expect((model.active, model.editing), (false, false));
          expect(find.text('Could not open link'), findsOneWidget);
          if (auto) {
            await _shortcut(tester, LogicalKeyboardKey.keyZ);
            expect(_canvas(tester).childOrder, ['editor', 'other']);
          }
        },
      );
    }
  }

  for (final kind in ['shape', 'text', 'code', 'title', 'media', 'pen', 'arrow']) {
    for (final device in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets('Auto $kind $device click promotes permanently without changing activation rules', (tester) async {
        final document = _autoDocument(kind);
        final target = document.elements.first.id;
        final store = TestLibraryStore(document);
        await pumpCanvas(tester, store);
        await tester.tapAt(_autoHitPoint(tester, kind), kind: device);
        await tester.pumpAndSettle();
        final expected = [...document.elements.skip(1).map((element) => element.id), target];
        expect(_canvas(tester).childOrder, expected);
        if (kind == 'pen') {
          expect(tester.widget<PenElementView>(find.byType(PenElementView)).resources.active, isFalse);
        }
        await tester.tapAt(const Offset(790, 590), kind: device);
        await tester.pumpAndSettle();
        expect(_canvas(tester).childOrder, expected);
        await pumpPastSave(tester);
        expect(_order(store.persisted!), expected);
        await tester.pumpWidget(const SizedBox());
        await pumpCanvas(tester, TestLibraryStore(store.persisted));
        expect(_canvas(tester).childOrder, expected);
      });
    }
    testWidgets('Auto inactive $kind drag promotes and moves in one undo step', (tester) async {
      final document = _autoDocument(kind);
      final initial = _order(document);
      final target = document.elements.first.id;
      await pumpCanvas(tester, TestLibraryStore(document));
      final controller = _canvas(tester);
      final position = controller.getInfo(target).gsPosition;
      final start = kind == 'media'
          ? tester.getCenter(find.byKey(const ValueKey('media-panel-drag-strip')))
          : _autoHitPoint(tester, kind);
      await tester.dragFrom(start, const Offset(45, 30), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(controller.childOrder.last, target);
      expect(controller.getInfo(target).gsPosition, position + const Offset(45, 30));
      await _shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(controller.childOrder, initial);
      expect(controller.getInfo(target).gsPosition, position);
      await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(controller.childOrder.last, target);
      expect(controller.getInfo(target).gsPosition, position + const Offset(45, 30));
    });
  }

  testWidgets('Auto mixed group drag promotes only enabled members in relative order', (tester) async {
    var document = _document();
    document = document.withElements((elements) => elements[0] = elements[0].copyWith(autoArrange: true));
    document = document.withElements((elements) => elements[2] = elements[2].copyWith(autoArrange: true));
    await pumpCanvas(tester, TestLibraryStore(document));
    final models = _models(tester);
    for (final id in ['a', 'b', 'c']) {
      models[id]!.setSelected(value: true);
    }
    final positions = {
      for (final id in ['a', 'b', 'c']) id: models[id]!.canvasPosition,
    };
    final drag = await tester.startGesture(const Offset(305, 305), kind: PointerDeviceKind.mouse);
    for (var update = 0; update < 3; update++) {
      await drag.moveBy(const Offset(15, 10));
      await tester.pump();
      expect(_canvas(tester).childOrder, ['b', 'd', 'a', 'c']);
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, ['b', 'd', 'a', 'c']);
    for (final id in positions.keys) {
      expect(models[id]!.canvasPosition, positions[id]! + const Offset(45, 30));
    }
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_canvas(tester).childOrder, ['a', 'b', 'c', 'd']);
    for (final id in positions.keys) {
      expect(models[id]!.canvasPosition, positions[id]);
    }
  });

  testWidgets('Auto modifier-click and right-click promote without activation', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document(auto: true)));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(const Offset(305, 305));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, ['b', 'c', 'd', 'a']);
    expect(_models(tester)['a']!.active, isFalse);
    expect(_models(tester)['a']!.selected, isTrue);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_canvas(tester).childOrder, ['a', 'b', 'c', 'd']);
    await _open(tester, const Offset(305, 305));
    expect(_canvas(tester).childOrder, ['b', 'c', 'd', 'a']);
    expect(_models(tester)['a']!.active, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_canvas(tester).childOrder, ['a', 'b', 'c', 'd']);
  });

  testWidgets('manual boundary choice disables Auto and undo restores its setting', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document(auto: true)));
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Arrange'));
    await tester.pumpAndSettle();
    final toggle = tester.widget<LabeledSwitch>(find.byType(LabeledSwitch));
    expect(toggle.value, isTrue);
    expect(toggle.focusNode!.hasFocus, isTrue);
    expect(tester.getSemantics(find.byType(LabeledSwitch)).flagsCollection.isToggled.toBoolOrNull(), isTrue);
    expect(_button(tester, 'Bring to Front').onPressed, isNotNull);
    await tester.tap(find.text('Bring to Front'));
    await tester.pumpAndSettle();
    expect(_models(tester)['a']!.autoArrange, isFalse);
    expect(_canvas(tester).childOrder, ['b', 'c', 'd', 'a']);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_models(tester)['a']!.autoArrange, isTrue);
    expect(_canvas(tester).childOrder, ['b', 'c', 'd', 'a']);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_canvas(tester).childOrder, ['a', 'b', 'c', 'd']);
  });

  testWidgets('Auto switch applies to a mixed group and promotes immediately in one step', (tester) async {
    final document = _document().withElements((elements) => elements[2] = elements[2].copyWith(autoArrange: true));
    await pumpCanvas(tester, TestLibraryStore(document));
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    _models(tester)['a']!.setSelected(value: true);
    _models(tester)['c']!.setSelected(value: true);
    await tester.tap(find.byTooltip('Arrange'));
    await tester.pumpAndSettle();
    expect(tester.widget<LabeledSwitch>(find.byType(LabeledSwitch)).value, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
    expect(_canvas(tester).childOrder, ['b', 'd', 'a', 'c']);
    expect(_models(tester)['a']!.autoArrange, isTrue);
    expect(_models(tester)['c']!.autoArrange, isTrue);
    expect(_models(tester)['b']!.autoArrange, isFalse);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_canvas(tester).childOrder, ['a', 'b', 'c', 'd']);
    expect(_models(tester)['a']!.autoArrange, isFalse);
    expect(_models(tester)['c']!.autoArrange, isTrue);
    await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(_canvas(tester).childOrder, ['b', 'd', 'a', 'c']);
    _models(tester)['a']!.setSelected(value: true);
    _models(tester)['c']!.setSelected(value: true);
    await _open(tester, const Offset(355, 355));
    await _openArrange(tester);
    expect(tester.widget<LabeledSwitch>(find.byType(LabeledSwitch)).value, isTrue);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, ['b', 'd', 'a', 'c']);
    expect(_models(tester)['a']!.autoArrange, isFalse);
    expect(_models(tester)['c']!.autoArrange, isFalse);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_models(tester)['a']!.autoArrange, isTrue);
    expect(_models(tester)['c']!.autoArrange, isTrue);
  });

  testWidgets('manual group shortcut disables Auto only for its targets', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document(auto: true)));
    _models(tester)['a']!.setSelected(value: true);
    _models(tester)['c']!.setSelected(value: true);
    await _shortcut(tester, LogicalKeyboardKey.bracketRight, shift: true);
    expect(_canvas(tester).childOrder, ['b', 'd', 'a', 'c']);
    expect(_models(tester)['a']!.autoArrange, isFalse);
    expect(_models(tester)['c']!.autoArrange, isFalse);
    expect(_models(tester)['b']!.autoArrange, isTrue);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_canvas(tester).childOrder, ['a', 'b', 'c', 'd']);
    expect(_models(tester)['a']!.autoArrange, isTrue);
    expect(_models(tester)['c']!.autoArrange, isTrue);
  });

  testWidgets('Auto menu toggle supports native hover and keyboard activation', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document(auto: true)));
    await _open(tester, const Offset(305, 305));
    await _openArrange(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(find.text('Send to Back')));
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Send to Back'))).hasFocus, isTrue);
    await mouse.moveTo(tester.getCenter(find.text('Auto')));
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Auto'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
    expect(_models(tester)['a']!.autoArrange, isFalse);
    await mouse.removePointer();
  });

  testWidgets('direct heading is noninteractive and navigation skips disabled commands', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await tester.tapAt(const Offset(375, 375));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Arrange'));
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.text('Arrange'), matching: find.byType(MenuItemButton)), findsNothing);
    expect(_button(tester, 'Bring Forward').onPressed, isNull);
    expect(_button(tester, 'Bring to Front').onPressed, isNull);
    expect(tester.widget<LabeledSwitch>(find.byType(LabeledSwitch)).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Send Backward'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Send to Back'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, ['d', 'a', 'b', 'c']);
    expect(find.byType(MenuSurface), findsNothing);
  });

  testWidgets('direct menu with no available commands can dismiss without saving', (tester) async {
    final document = _document().withElements((elements) => elements.removeRange(1, 4));
    final store = TestLibraryStore(document);
    await pumpCanvas(tester, store);
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Arrange'));
    await tester.pumpAndSettle();
    for (final label in ['Bring Forward', 'Send Backward', 'Bring to Front', 'Send to Back']) {
      expect(_button(tester, label).onPressed, isNull);
    }
    await tester.tap(find.text('Bring Forward'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
    expect(_models(tester)['a']!.selected, isTrue);
    await pumpPastSave(tester);
    expect(store.persisted, isNull);
  });

  for (final escape in [false, true]) {
    testWidgets('direct ${escape ? 'Escape preserves' : 'click-away clears'} single selection', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document()));
      await tester.tapAt(const Offset(305, 305));
      await tester.pumpAndSettle();
      _models(tester)['c']!.setSelected(value: true);
      _models(tester)['d']!.setSelected(value: true);
      await tester.tap(find.byTooltip('Arrange'));
      await tester.pumpAndSettle();
      expect(_models(tester).values.where((model) => model.selected).map((model) => model.data.id), ['a']);
      if (escape) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tapAt(const Offset(790, 590));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MenuSurface), findsNothing);
      expect(_models(tester)['a']!.selected, escape);
      expect(_models(tester)['a']!.active, isFalse);
    });
  }

  for (final device in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    for (final escape in [false, true]) {
      testWidgets('direct group $device Arrange restores selection and dismisses with Escape $escape', (tester) async {
        final store = TestLibraryStore(_document());
        await pumpCanvas(tester, store);
        await tester.tapAt(const Offset(305, 305));
        await tester.pumpAndSettle();
        final models = _models(tester);
        models['a']!.setSelected(value: true);
        models['c']!.setSelected(value: true);
        await tester.pump();
        final click = await tester.startGesture(tester.getCenter(find.byTooltip('Arrange')), kind: device);
        expect(models['a']!.selected, isFalse);
        expect(models['c']!.selected, isFalse);
        await click.up();
        await tester.pumpAndSettle();
        expect(models['a']!.selected, isTrue);
        expect(models['c']!.selected, isTrue);
        expect(models['b']!.selected, isFalse);
        expect(models['a']!.active, isFalse);
        expect(find.byType(MenuSurface), findsOneWidget);
        expect(find.byType(ElementTransformControls), findsNothing);
        expect(tester.widget<LabeledSwitch>(find.byType(LabeledSwitch)).focusNode!.hasFocus, isTrue);
        if (escape) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tapAt(const Offset(790, 590), kind: device);
        }
        await tester.pumpAndSettle();
        expect(find.byType(MenuSurface), findsNothing);
        expect(models['a']!.selected, escape);
        expect(models['c']!.selected, escape);
        await pumpPastSave(tester);
        expect(store.persisted, isNull);
      });
    }
  }

  testWidgets('direct mixed group Arrange captures targets and saves order and Auto in one step', (tester) async {
    final document = _document().withElements((elements) => elements[2] = elements[2].copyWith(autoArrange: true));
    final store = TestLibraryStore(document);
    await pumpCanvas(tester, store);
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    final models = _models(tester);
    models['a']!.setSelected(value: true);
    models['c']!.setSelected(value: true);
    await tester.pump();
    await tester.tap(find.byTooltip('Arrange'));
    await tester.pumpAndSettle();
    expect(tester.widget<LabeledSwitch>(find.byType(LabeledSwitch)).value, isFalse);
    models['a']!.setSelected(value: false);
    models['c']!.setSelected(value: false);
    models['b']!.setSelected(value: true);
    await _shortcut(tester, LogicalKeyboardKey.bracketRight, shift: true);
    expect(_canvas(tester).childOrder, ['b', 'd', 'a', 'c']);
    expect(models['a']!.autoArrange, isFalse);
    expect(models['c']!.autoArrange, isFalse);
    await pumpPastSave(tester);
    expect(_order(store.persisted!), ['b', 'd', 'a', 'c']);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(_canvas(tester).childOrder, ['a', 'b', 'c', 'd']);
    expect(models['c']!.autoArrange, isTrue);
    await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(_canvas(tester).childOrder, ['b', 'd', 'a', 'c']);
    expect(models['c']!.autoArrange, isFalse);
  });

  for (final editor in ['text', 'code', 'title', 'media']) {
    testWidgets('direct $editor Arrange ends editing and transfers focus', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_editorDocument(editor)));
      final surface = switch (editor) {
        'text' => find.byKey(const ValueKey('text-markdown-preview')),
        'title' => find.byKey(const ValueKey('code-title-text')),
        'code' => find.byKey(const ValueKey('code-block-preview-surface')),
        _ => find.byKey(const ValueKey('media-url-field')),
      };
      await tester.tapAt(tester.getCenter(surface));
      await tester.pumpAndSettle();
      final focus = switch (editor) {
        'text' => tester.widget<TextElementView>(find.byType(TextElementView)).resources.focusNode,
        'code' || 'title' => tester.widget<CodeElementView>(find.byType(CodeElementView)).resources.focusNode,
        _ => tester.widget<MediaElementView>(find.byType(MediaElementView)).resources.focusNode,
      };
      await tester.tap(find.byTooltip('Arrange'));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(find.byType(ElementTransformControls), findsNothing);
      expect(tester.widget<LabeledSwitch>(find.byType(LabeledSwitch)).focusNode!.hasFocus, isTrue);
      if (editor == 'text') {
        final model = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
        expect(model.editing, isFalse);
        expect(model.controller.text, 'contents');
      } else if (editor == 'code' || editor == 'title') {
        final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
        expect(model.controller.text, 'contents');
        expect(model.title, 'Title');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
    });
  }

  testWidgets('direct shortcuts use captured targets and navigation dismisses the popover', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Arrange'));
    await tester.pumpAndSettle();
    _models(tester)['a']!.setSelected(value: false);
    _models(tester)['c']!.setSelected(value: true);
    await _shortcut(tester, LogicalKeyboardKey.bracketRight, shift: true);
    expect(_canvas(tester).childOrder, ['b', 'c', 'd', 'a']);
    expect(find.byType(MenuSurface), findsNothing);
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Arrange'));
    await tester.pumpAndSettle();
    _canvas(tester).updateScalebyDelta(0.1);
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
  });

  for (final style in SurfaceStyle.values) {
    for (final (position, rotation, scale) in [
      (const Offset(100, 130), 0.0, 1.0),
      (const Offset(650, 330), 0.0, 1.0),
      (const Offset(500, 470), 0.0, 1.0),
      (const Offset(240, 130), math.pi / 4, 1.5),
    ]) {
      testWidgets('direct $style popover stays upright and bounded at $position, $rotation, $scale', (tester) async {
        var document = _editorDocument('code').withElements((elements) => elements.removeLast());
        document = document.withElements(
          (elements) => elements[0] = (elements.first as CodeElementData).copyWith(
            position: position,
            rotation: rotation,
            size: codeBlockMinimumSize,
          ),
        );
        await pumpCanvas(tester, TestLibraryStore(document));
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        await tester.pumpWidget(
          MaterialApp(
            theme: app.theme!.copyWith(extensions: [app.theme!.extension<BTheme>()!.copyWith(surfaceStyle: style)]),
            home: app.home,
          ),
        );
        _canvas(tester).updateScalebyDelta(scale - 1, focalPoint: Offset.zero);
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('code-title-text'))));
        await tester.pumpAndSettle();
        final trigger = tester.renderObject<RenderBox>(find.byTooltip('Arrange'));
        final bounds = MatrixUtils.transformRect(trigger.getTransformTo(null), Offset.zero & trigger.size);
        await tester.tap(find.byTooltip('Arrange'));
        await tester.pumpAndSettle();
        final menu = tester.getRect(find.byType(MenuSurface));
        expect(menu.left, greaterThanOrEqualTo(0));
        expect(menu.top, greaterThanOrEqualTo(0));
        expect(menu.right, lessThanOrEqualTo(800));
        expect(menu.bottom, lessThanOrEqualTo(600));
        if (position.dx == 100) {
          expect(menu.left, greaterThan(bounds.right));
        } else {
          expect(menu.right, lessThan(bounds.left));
        }
        final row = tester.getRect(find.byType(MenuItemButton).first);
        expect(row.width, greaterThan(row.height));
        expect(
          find.descendant(of: find.byType(MenuSurface), matching: find.byType(GlassSurface)),
          style == SurfaceStyle.glass ? findsOneWidget : findsNothing,
        );
      });
    }
  }

  for (final (group, direct) in [(false, false), (true, false), (false, true)]) {
    for (final (label, target, expected) in [
      ('Bring Forward', 'a', group ? ['b', 'd', 'a', 'c'] : ['b', 'a', 'c', 'd']),
      ('Send Backward', 'd', group ? ['b', 'd', 'a', 'c'] : ['a', 'b', 'd', 'c']),
      ('Bring to Front', 'a', group ? ['b', 'd', 'a', 'c'] : ['b', 'c', 'd', 'a']),
      ('Send to Back', 'd', group ? ['b', 'd', 'a', 'c'] : ['d', 'a', 'b', 'c']),
    ]) {
      testWidgets(
        '${direct ? 'direct' : 'submenu'} $label saves ${group ? 'group' : 'single'} order',
        (tester) async {
          final store = TestLibraryStore(_document());
          await pumpCanvas(tester, store);
          final canvas = _canvas(tester);
          final before = _models(tester);
          final original = {for (final data in store.initial!.elements) data.id: data.toJson()};
          if (group) {
            before[target]!.setSelected(value: true);
            before[target == 'a' ? 'c' : 'b']!.setSelected(value: true);
          }
          final position = before[target]!.data.position + const Offset(5, 5);
          if (direct) {
            await tester.tapAt(position);
            await tester.pumpAndSettle();
            expect(before[target]!.active, isTrue);
            await tester.tap(find.byTooltip('Arrange'));
            await tester.pumpAndSettle();
            expect(find.byType(SubmenuButton), findsNothing);
            expect(find.byType(MenuItemButton), findsNWidgets(5));
            expect(find.text('Arrange'), findsOneWidget);
            expect(find.byType(ElementTransformControls), findsNothing);
            expect(before[target]!.active, isFalse);
            expect(before[target]!.selected, isTrue);
            expect(canvas.childOrder, ['a', 'b', 'c', 'd']);
            expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).foregroundChildId, isNull);
          } else {
            await _open(tester, position);
            await _openArrange(tester);
          }
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.byType(MenuSurface), findsNothing);
          expect(canvas.childOrder, expected);
          final after = _models(tester);
          for (final id in before.keys) {
            expect(after[id], equals(before[id]));
            expect(after[id]!.data.toJson(), original[id]);
          }
          expect(after[target]!.selected, isTrue);
          expect(after[target]!.active, isFalse);
          await pumpPastSave(tester);
          expect(_order(store.persisted!), expected);
          await _shortcut(tester, LogicalKeyboardKey.keyZ);
          expect(canvas.childOrder, ['a', 'b', 'c', 'd']);
          for (final id in before.keys) {
            expect(_models(tester)[id], equals(before[id]));
          }
          await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
          expect(canvas.childOrder, expected);
          await _shortcut(tester, LogicalKeyboardKey.keyZ);
          await _shortcut(tester, LogicalKeyboardKey.keyZ);
          expect(canvas.childOrder, ['a', 'b', 'c', 'd']);
          for (final id in before.keys) {
            expect(_models(tester)[id], equals(before[id]));
          }
          await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
          await pumpPastSave(tester);
          await tester.pumpWidget(const SizedBox());
          await pumpCanvas(tester, TestLibraryStore(store.persisted));
          expect(_canvas(tester).childOrder, expected);
        },
      );
    }
  }

  for (final tool in ['media', 'code']) {
    testWidgets('$tool Arrange tooltip follows layout through transforms', (tester) async {
      await pumpCanvas(
        tester,
        TestLibraryStore(_editorDocument(tool)),
        attachmentStore: TestAttachmentStore(),
      );
      if (tool == 'media') {
        final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
        await tester.runAsync(() => model.setDeviceImage(onePixelPngBytes, 'png'));
      }
      await tester.pumpAndSettle();
      final surface = find.byKey(ValueKey(tool == 'media' ? 'media-image' : 'code-block-preview-surface'));
      await tester.tap(surface);
      await tester.pumpAndSettle();
      final model =
          (tool == 'media'
                  ? tester.widget<MediaElementView>(find.byType(MediaElementView)).resources
                  : tester.widget<CodeElementView>(find.byType(CodeElementView)).resources)
              as ElementResources;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));

      Future<void> hoverArrange() async {
        await mouse.moveTo(tester.getCenter(find.byTooltip('Arrange')));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Arrange'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      void expectAttached() {
        final body = tester.renderObject<RenderBox>(
          find.byKey(ValueKey(tool == 'media' ? 'media-image' : 'code-block-surface')),
        );
        final controls = tester.renderObject<RenderBox>(find.byType(ElementTransformControls));
        final expected = body.localToGlobal(Offset(-ElementTransformControls.size.width - 10, 0));
        expect((controls.localToGlobal(Offset.zero) - expected).distance, lessThan(0.001));
      }

      expectAttached();
      await hoverArrange();
      await mouse.moveTo(const Offset(790, 590));
      await tester.pumpAndSettle();
      final transform = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('$tool-block-handle'))),
        kind: PointerDeviceKind.mouse,
      );
      final controls = tester.widget<ElementTransformControls>(find.byType(ElementTransformControls));
      controls.onMove(const Offset(20, -110));
      controls.onRotate!(math.pi / 6);
      await transform.cancel();
      _canvas(tester).updateScalebyDelta(0.25, focalPoint: Offset.zero);
      await tester.pumpAndSettle();
      expectAttached();
      final resizeHandle = find.byKey(ValueKey(tool == 'media' ? 'media-resize-handle' : 'code-block-resize-handle'));
      final oldSize = model.canvasSize;
      final resize = await tester.startGesture(tester.getCenter(resizeHandle), kind: PointerDeviceKind.mouse);
      for (var step = 0; step < 2; step++) {
        await resize.moveBy(const Offset(15, 20));
        await tester.pump();
        expectAttached();
      }
      await resize.up();
      await tester.pumpAndSettle();
      expect(model.canvasSize.width, greaterThan(oldSize.width));
      await hoverArrange();
      await mouse.down(tester.getCenter(find.byTooltip('Arrange')));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(MenuSurface), findsOneWidget);
      expect(model.active, isFalse);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    });
  }

  testWidgets('code title and body share temporary foreground and saved arrangement', (tester) async {
    var document = _editorDocument('code');
    document = document.withElements(
      (elements) => elements[elements.length - 1] = (elements.last as ShapeElementData).copyWith(
        position: const Offset(150, 195),
        size: const Size(100, 110),
        fillColor: Colors.red,
      ),
    );
    final store = TestLibraryStore(document);
    await pumpCanvas(tester, store);
    await tester.pumpAndSettle();
    final canvas = _canvas(tester);
    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    final editorState = tester.state(find.byType(CodeElementView));
    final title = tester.getCenter(find.byKey(const ValueKey('code-title-text')));
    const body = Offset(180, 280);

    Future<void> expectCovered({required bool covered}) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.ancestor(of: find.byType(LazyCanvas), matching: find.byType(RepaintBoundary)).first,
      );
      final pixels = await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return await image.toByteData();
        } finally {
          image.dispose();
        }
      });
      for (final point in [const Offset(155, 213), body]) {
        final local = boundary.globalToLocal(point);
        final index = (local.dy.toInt() * boundary.size.width.toInt() + local.dx.toInt()) * 4;
        final pixel = Color.fromARGB(
          pixels!.getUint8(index + 3),
          pixels.getUint8(index),
          pixels.getUint8(index + 1),
          pixels.getUint8(index + 2),
        );
        expect(pixel.toARGB32() == Colors.red.toARGB32(), covered, reason: 'at $point, pixel $pixel');
      }
      expect(canvas.childOrder, ['editor', 'other']);
      expect(tester.state(find.byType(CodeElementView)), same(editorState));
    }

    await expectCovered(covered: true);
    await tester.tapAt(title);
    await tester.pumpAndSettle();
    expect(model.active, isFalse);
    expect(_models(tester)['other']!.active, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 350)); // Exposed code body.
    await tester.pumpAndSettle();
    expect(model.active, isTrue);
    expect(tester.widget<LazyCanvas>(find.byType(LazyCanvas)).foregroundChildId, 'editor');
    await expectCovered(covered: false);
    await tester.tapAt(title);
    await tester.pumpAndSettle();
    expect(model.active, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await expectCovered(covered: true);
    await pumpPastSave(tester);
    expect(store.persisted, isNull);

    await tester.tapAt(const Offset(400, 350));
    await tester.pumpAndSettle();
    await _open(tester, title); // Capture lifted code before revealing the covering shape.
    expect(model.active, isFalse);
    expect(model.selected, isTrue);
    expect(_models(tester)['other']!.selected, isFalse);
    await expectCovered(covered: true);
    await _openArrange(tester);
    await tester.tap(find.text('Bring Forward'));
    await tester.pumpAndSettle();
    expect(canvas.childOrder, ['other', 'editor']);
    expect(model.active, isFalse);
    await tester.tapAt(title);
    await tester.pumpAndSettle();
    expect(model.active, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(canvas.childOrder, ['other', 'editor']);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('code title preserves body geometry and transforms at zoom $scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var document = _editorDocument('code').withElements((elements) => elements.removeLast());
      document = document.withElements(
        (elements) => elements[0] = (elements.first as CodeElementData).copyWith(position: const Offset(100, 100)),
      );
      await pumpCanvas(tester, TestLibraryStore(document));
      final canvas = _canvas(tester)..updateScalebyDelta(scale - 1, focalPoint: Offset.zero);
      await tester.pumpAndSettle();
      final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
      RenderBox body() => tester.renderObject<RenderBox>(find.byKey(const ValueKey('code-block-surface')));
      void expectGeometry() {
        final center = (model.data.position + model.size.center(Offset.zero) - canvas.offset) * scale;
        expect((body().localToGlobal(model.size.center(Offset.zero)) - center).distance, lessThan(0.001));
        expect(body().size, model.size);
        final title = tester.renderObject<RenderBox>(
          find.byKey(ValueKey(model.active ? 'code-title-input-tab' : 'code-title-tab')),
        );
        expect(
          (title.localToGlobal(Offset(0, title.size.height)) - body().localToGlobal(Offset.zero)).distance,
          lessThan(0.001),
        );
        if (model.active) {
          final controls = tester.widget<ElementTransformControls>(find.byType(ElementTransformControls));
          expect((controls.rotationCenter() - center).distance, lessThan(0.001));
          final controlsBox = tester.renderObject<RenderBox>(find.byType(ElementTransformControls));
          final anchor = body().localToGlobal(Offset(-ElementTransformControls.size.width - 10, 0));
          expect((controlsBox.localToGlobal(Offset.zero) - anchor).distance, lessThan(0.001));
        }
      }

      expectGeometry();
      final original = model.data.position;
      const delta = Offset(50, 30);
      final titleCenter = tester.getCenter(find.byKey(const ValueKey('code-title-text')));
      final drag = await tester.startGesture(titleCenter, kind: PointerDeviceKind.mouse);
      await drag.moveBy(delta);
      await drag.up();
      await tester.pumpAndSettle();
      expect((model.data.position - original - delta / scale).distance, lessThan(0.001));
      expect(model.active, isFalse);
      expectGeometry();
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('code-title-text'))));
      await tester.pumpAndSettle();
      expect(model.active, isTrue);
      final controls = tester.widget<ElementTransformControls>(find.byType(ElementTransformControls));
      controls.onMove(const Offset(-20, -10));
      controls.onRotate!(math.pi / 3);
      await tester.pumpAndSettle();
      expectGeometry();
      final oldSize = model.size;
      final resize = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('code-block-resize-handle'))),
      );
      final screenDelta =
          Offset(
            math.cos(model.rotation) * 20 - math.sin(model.rotation) * 10,
            math.sin(model.rotation) * 20 + math.cos(model.rotation) * 10,
          ) *
          scale;
      await resize.moveBy(screenDelta);
      await resize.moveBy(screenDelta);
      await resize.up();
      await tester.pumpAndSettle();
      expect(model.size.width, greaterThan(oldSize.width));
      expect(model.size.height, greaterThan(oldSize.height));
      expect(model.active, isTrue);
      expectGeometry();
      final bounds = (model.canvasPosition, model.canvasSize);
      model.setTitle('');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(model.active, isFalse);
      expect((model.canvasPosition, model.canvasSize), bounds);
      expect(find.byKey(const ValueKey('code-title-hidden')), findsOneWidget);
    });
  }

  testWidgets('submenu has native keyboard navigation and disabled actions', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await _open(tester, const Offset(375, 375));
    expect(find.text('Arrange'), findsOneWidget);
    expect(find.text('Bring Forward'), findsNothing);
    expect(_models(tester)['d']!.selected, isTrue);
    for (var step = 0; step < 3; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();
    expect(find.text('Bring Forward'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Bring Forward'), findsOneWidget);
    expect(_button(tester, 'Bring Forward').onPressed, isNull);
    expect(_button(tester, 'Bring to Front').onPressed, isNull);
    expect(_button(tester, 'Send Backward').onPressed, isNotNull);
    expect(_button(tester, 'Send to Back').onPressed, isNotNull);
    expect(tester.widget<LabeledSwitch>(find.byType(LabeledSwitch)).value, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, ['a', 'b', 'd', 'c']);
    expect(find.text('Arrange'), findsNothing);
    await _open(tester, const Offset(375, 375));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Arrange'), findsNothing);
    expect(_models(tester)['c']!.selected, isTrue);
  });

  for (final kind in ['text', 'code', 'title']) {
    for (final sameObject in [false, true]) {
      for (final multiple in [false, true]) {
        testWidgets(
          '$kind outside click activates after ${sameObject ? 'same' : 'other'} object menu, group=$multiple',
          (
            tester,
          ) async {
            await pumpCanvas(tester, TestLibraryStore(_editorDocument(kind)));
            final point = _autoHitPoint(tester, kind);
            final model = kind == 'text'
                ? tester.widget<TextElementView>(find.byType(TextElementView)).resources as ElementResources
                : tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
            final other = _models(tester)['other']!;
            model.setSelected(value: sameObject || multiple);
            other.setSelected(value: !sameObject || multiple);
            await _open(tester, sameObject ? point : const Offset(555, 405));
            await tester.tapAt(point - const Offset(25, 0));
            await tester.pumpAndSettle();
            expect(find.byType(MenuSurface), findsNothing);
            expect(model.active, isTrue);
            expect(model.selected, isFalse);
            expect(other.selected, isFalse);
            if (kind == 'text') {
              final text = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
              expect(text.editing, isTrue);
              expect(text.focusNode.hasFocus, isTrue);
              expect(text.controller.text, 'contents');
            } else {
              final code = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
              expect(code.focusNode.hasFocus, isTrue);
              expect(code.controller.text, 'contents');
              expect(code.title, 'Title');
            }
          },
        );
      }
    }
  }

  testWidgets('outside modifier-click toggles selection and selected drag keeps the group', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    final models = _models(tester);
    models['a']!.setSelected(value: true);
    models['c']!.setSelected(value: true);
    await _open(tester, const Offset(355, 355));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(const Offset(330, 330));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
    expect(models['a']!.selected, isTrue);
    expect(models['b']!.selected, isTrue);
    expect(models['c']!.selected, isTrue);
    expect(models.values.every((model) => !model.active), isTrue);

    await _open(tester, const Offset(355, 355));
    final before = {for (final entry in models.entries) entry.key: entry.value.canvasPosition};
    await tester.dragFrom(const Offset(305, 305), const Offset(-40, -20));
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
    for (final id in ['a', 'b', 'c']) {
      expect(models[id]!.selected, isTrue);
      expect(models[id]!.canvasPosition, before[id]! - const Offset(40, 20));
      expect(models[id]!.active, isFalse);
    }
    expect(models['d']!.canvasPosition, before['d']);
  });

  testWidgets('menu padding stays inside and a toolbar click dismisses and clears selection', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await _open(tester, const Offset(305, 305));
    await tester.tapAt(tester.getTopLeft(find.byType(MenuSurface)) + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsOneWidget);
    expect(_models(tester)['a']!.selected, isTrue);
    await _openArrange(tester);
    final submenu = find.byType(MenuSurface).last;
    await tester.tapAt(tester.getTopLeft(submenu) + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNWidgets(2));
    expect(_models(tester)['a']!.selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuSurface), findsNothing);
    expect(_models(tester).values.every((model) => !model.selected), isTrue);
    expect(tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).selected, isTrue);
  });

  testWidgets('outside right-click replaces the menu targets', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await _open(tester, const Offset(375, 375));
    await _open(tester, const Offset(305, 305));
    expect(find.byType(MenuSurface), findsOneWidget);
    expect(_models(tester)['a']!.selected, isTrue);
    expect(_models(tester)['d']!.selected, isFalse);
  });

  testWidgets('Arrange outside editor click clears selection and resumes editing', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_editorDocument('code')));
    final point = _autoHitPoint(tester, 'code');
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Arrange'));
    await tester.pumpAndSettle();
    final outside =
        tester.getTopRight(find.byKey(const ValueKey('code-block-preview-surface'))) + const Offset(-10, 100);
    expect(tester.getRect(find.byType(MenuSurface)).contains(outside), isFalse);
    await tester.tapAt(outside);
    await tester.pumpAndSettle();
    final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
    expect(find.byType(MenuSurface), findsNothing);
    expect(model.selected, isFalse);
    expect(model.active, isTrue);
    expect(model.focusNode.hasFocus, isTrue);
  });

  testWidgets('hover opens the submenu and click-away clears selection', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    final model = _models(tester)['a']!;
    expect(model.active, isTrue);
    await _open(tester, const Offset(305, 305));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(const Offset(790, 590));
    await mouse.moveTo(tester.getCenter(find.text('Arrange')));
    await tester.pumpAndSettle();
    expect(find.text('Bring Forward'), findsOneWidget);
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    expect(model.selected, isFalse);
    expect(model.active, isFalse);
    expect(find.text('Arrange'), findsNothing);
    await mouse.removePointer();
  });

  for (final scale in [1.0, 2.0]) {
    for (final jitter in [3.0, 4.0]) {
      testWidgets('right-click tolerates $jitter pixels of jitter at zoom $scale', (tester) async {
        await pumpCanvas(tester, TestLibraryStore(_document()));
        final canvas = _canvas(tester)..updateScalebyDelta(scale - 1);
        await tester.pumpAndSettle();
        final models = _models(tester);
        models['a']!.setSelected(value: true);
        final before = canvas.offset;
        final position = canvas.getInfo('c').ssPosition + const Offset(5, 5);
        final click = await tester.startGesture(position, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
        for (final delta in [Offset(jitter, 0), Offset(-jitter, 0), Offset(jitter, 0)]) {
          await click.moveBy(delta);
          await tester.pump();
          expect(canvas.offset, before);
          expect(models['a']!.selected, isTrue);
          expect(find.text('Arrange'), findsNothing);
        }
        await click.up();
        await tester.pumpAndSettle();
        expect(canvas.offset, before);
        expect(find.text('Arrange'), findsOneWidget);
        expect(models['a']!.selected, isFalse);
        expect(models['c']!.selected, isTrue);
        expect(models['c']!.active, isFalse);
      });
    }

    testWidgets('right-drag commits beyond four pixels even when returning to the press at zoom $scale', (
      tester,
    ) async {
      await pumpCanvas(tester, TestLibraryStore(_document()));
      final canvas = _canvas(tester)..updateScalebyDelta(scale - 1);
      await tester.pumpAndSettle();
      final model = _models(tester)['a']!..setSelected(value: true);
      final before = canvas.offset;
      final position = canvas.getInfo('c').ssPosition + const Offset(5, 5);
      final drag = await tester.startGesture(position, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
      await drag.moveBy(const Offset(3, 0));
      expect(canvas.offset, before);
      await drag.moveBy(const Offset(2, 0));
      expect(canvas.offset, before - const Offset(5, 0) / scale);
      await drag.moveTo(position);
      expect(canvas.offset, before);
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('Arrange'), findsNothing);
      expect(model.selected, isTrue);
      await _open(tester, position);
      expect(find.text('Arrange'), findsOneWidget);
    });
  }

  testWidgets('empty-canvas right-click jitter ends activation and preserves selection', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    final model = _models(tester)['a']!..setSelected(value: true);
    final canvas = _canvas(tester);
    final before = canvas.offset;
    final click = await tester.startGesture(
      const Offset(200, 550),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await click.moveBy(const Offset(3, 0));
    await click.up();
    await tester.pumpAndSettle();
    expect(canvas.offset, before);
    expect(model.active, isFalse);
    expect(model.selected, isTrue);
    expect(find.text('Arrange'), findsNothing);
    expect(find.text('Paste'), findsOneWidget);
  });

  for (final displacement in [const Offset(3, 0), const Offset(30, 0)]) {
    testWidgets('canceling right-click or pan at $displacement clears the gesture without inertia', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document()));
      final canvas = _canvas(tester);
      final drag = await tester.startGesture(
        const Offset(355, 355),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await drag.moveBy(displacement, timeStamp: const Duration(milliseconds: 16));
      await drag.moveBy(displacement, timeStamp: const Duration(milliseconds: 32));
      await drag.cancel();
      final frozen = canvas.offset;
      await tester.pump(const Duration(milliseconds: 200));
      expect(canvas.offset, frozen);
      expect(find.text('Arrange'), findsNothing);
      await _open(tester, canvas.getInfo('c').ssPosition + const Offset(5, 5));
      expect(find.text('Arrange'), findsOneWidget);
    });
  }

  testWidgets('tool changes cancel a right-drag through final release', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    final canvas = _canvas(tester);
    final drag = await tester.startGesture(
      const Offset(355, 355),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await drag.moveBy(const Offset(30, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    final frozen = canvas.offset;
    await drag.moveBy(const Offset(30, 0));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(canvas.offset, frozen);
    expect(find.text('Arrange'), findsNothing);
    await _open(tester, canvas.getInfo('c').ssPosition + const Offset(5, 5));
    expect(find.text('Arrange'), findsOneWidget);
  });

  testWidgets('right-click stops existing inertia before deciding whether to pan', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    final canvas = _canvas(tester)
      ..onScaleStart(ScaleStartDetails())
      ..onScaleEnd(ScaleEndDetails(velocity: const Velocity(pixelsPerSecond: Offset(500, 0))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(canvas.offset, isNot(Offset.zero));
    final before = canvas.offset;
    final click = await tester.startGesture(
      canvas.getInfo('c').ssPosition + const Offset(5, 5),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await click.moveBy(const Offset(3, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(canvas.offset, before);
    await click.up();
    await tester.pumpAndSettle();
    expect(canvas.offset, before);
    expect(find.text('Arrange'), findsOneWidget);
  });

  testWidgets('right-click replaces selection and right-drag still pans', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    final before = _models(tester);
    before['a']!.setSelected(value: true);
    before['b']!.setSelected(value: true);
    final drag = await tester.startGesture(
      const Offset(355, 355),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await drag.moveBy(const Offset(50, 20));
    await drag.moveBy(const Offset(40, 20));
    await drag.up();
    await tester.pumpAndSettle();
    expect(_canvas(tester).offset, isNot(Offset.zero));
    expect(find.text('Arrange'), findsNothing);
    expect(before['a']!.selected, isTrue);
    expect(before['b']!.selected, isTrue);
    expect(before['c']!.data.position, const Offset(350, 350));
    final position = _canvas(tester).getInfo('c').ssPosition + const Offset(5, 5);
    await _open(tester, position);
    expect(before['a']!.selected, isFalse);
    expect(before['b']!.selected, isFalse);
    expect(before['c']!.selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _open(tester, const Offset(750, 500));
    expect(find.text('Arrange'), findsNothing);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
    testWidgets('$platform shortcuts support all commands, repeats, and active fallback', (tester) async {
      await pumpCanvas(tester, TestLibraryStore(_document()), platform: platform);
      await tester.tapAt(const Offset(305, 305));
      await tester.pumpAndSettle();
      final model = _models(tester)['a']!;
      final canvas = _canvas(tester);
      await _shortcut(tester, LogicalKeyboardKey.bracketLeft, platform: platform);
      expect(canvas.childOrder, ['a', 'b', 'c', 'd']);
      expect(model.active, isFalse);
      expect(model.selected, isTrue);
      await _shortcut(tester, LogicalKeyboardKey.bracketRight, platform: platform);
      expect(canvas.childOrder, ['b', 'a', 'c', 'd']);
      await _shortcut(tester, LogicalKeyboardKey.bracketRight, platform: platform, repeat: true);
      expect(canvas.childOrder, ['b', 'c', 'd', 'a']);
      await _shortcut(tester, LogicalKeyboardKey.bracketLeft, platform: platform);
      expect(canvas.childOrder, ['b', 'c', 'a', 'd']);
      await _shortcut(tester, LogicalKeyboardKey.bracketLeft, platform: platform, shift: true);
      expect(canvas.childOrder, ['a', 'b', 'c', 'd']);
      await _shortcut(tester, LogicalKeyboardKey.bracketRight, platform: platform, shift: true);
      expect(canvas.childOrder, ['b', 'c', 'd', 'a']);
      expect(_models(tester)['a'], equals(model));
      expect(model.active, isFalse);
      expect(model.selected, isTrue);
      await _shortcut(tester, LogicalKeyboardKey.braceLeft, platform: platform, shift: true);
      expect(canvas.childOrder, ['a', 'b', 'c', 'd']);
      await _shortcut(tester, LogicalKeyboardKey.braceRight, platform: platform, shift: true);
      expect(canvas.childOrder, ['b', 'c', 'd', 'a']);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await _shortcut(tester, LogicalKeyboardKey.bracketLeft, platform: platform, shift: true);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(canvas.childOrder, ['b', 'c', 'd', 'a']);
      await _shortcut(
        tester,
        LogicalKeyboardKey.bracketLeft,
        platform: platform == TargetPlatform.macOS ? TargetPlatform.linux : TargetPlatform.macOS,
        shift: true,
      );
      expect(canvas.childOrder, ['b', 'c', 'd', 'a']);
    });
  }

  testWidgets('menu shortcuts use captured targets and block unrelated canvas keys', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await _open(tester, const Offset(305, 305));
    _models(tester)['a']!.setSelected(value: false);
    _models(tester)['c']!.setSelected(value: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await _shortcut(tester, LogicalKeyboardKey.bracketRight, shift: true);
    expect(_canvas(tester).childOrder, ['b', 'c', 'd', 'a']);
    expect(find.text('Arrange'), findsNothing);
  });

  for (final editor in ['text', 'code', 'title', 'media']) {
    testWidgets('$editor right-click transfers focus and deactivates without changing content', (tester) async {
      final store = TestLibraryStore(_editorDocument(editor));
      await pumpCanvas(tester, store);
      final surface = switch (editor) {
        'text' => find.byKey(const ValueKey('text-markdown-preview')),
        'title' => find.byKey(const ValueKey('code-title-text')),
        'code' => find.byKey(const ValueKey('code-block-preview-surface')),
        _ => find.byKey(const ValueKey('media-url-field')),
      };
      await tester.tapAt(tester.getCenter(surface));
      await tester.pumpAndSettle();
      final focus = switch (editor) {
        'text' => tester.widget<TextElementView>(find.byType(TextElementView)).resources.focusNode,
        'code' || 'title' => tester.widget<CodeElementView>(find.byType(CodeElementView)).resources.focusNode,
        _ => tester.widget<MediaElementView>(find.byType(MediaElementView)).resources.focusNode,
      };
      final editingSurface = switch (editor) {
        'text' => find.byKey(const ValueKey('text-markdown-editor')),
        'title' => find.byKey(const ValueKey('code-title-input')),
        'code' => find.byKey(const ValueKey('code-block-preview-surface')),
        _ => find.byKey(const ValueKey('media-url-field')),
      };
      await tester.tap(editingSurface);
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.bracketRight, shift: true);
      expect(_canvas(tester).childOrder, ['editor', 'other']);
      final before = _canvas(tester).offset;
      await _open(tester, tester.getCenter(editingSurface), jitter: const Offset(3, 0));
      expect(_canvas(tester).offset, before);
      expect(find.text('Arrange'), findsOneWidget);
      expect(focus.hasFocus, isFalse);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      if (editor == 'text') {
        final model = tester.widget<TextElementView>(find.byType(TextElementView)).resources;
        expect(model.active, isFalse);
        expect(model.editing, isFalse);
        expect(model.controller.text, 'contents');
      } else if (editor == 'code' || editor == 'title') {
        final model = tester.widget<CodeElementView>(find.byType(CodeElementView)).resources;
        expect(model.active, isFalse);
        expect(model.controller.text, 'contents');
        expect(model.title, 'Title');
      } else {
        expect(tester.widget<MediaElementView>(find.byType(MediaElementView)).resources.active, isFalse);
      }
      await _shortcut(tester, LogicalKeyboardKey.bracketRight, shift: true);
      expect(_canvas(tester).childOrder, ['other', 'editor']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Arrange'), findsNothing);
      expect(focus.hasFocus, isFalse);
      expect(_canvas(tester).childOrder, ['other', 'editor']);
    });
  }

  testWidgets('image Arrange ends activation and reopening captures the inactive image', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_editorDocument('media')), attachmentStore: TestAttachmentStore());
    final model = tester.widget<MediaElementView>(find.byType(MediaElementView)).resources;
    await tester.runAsync(() => model.setDeviceImage(onePixelPngBytes, 'png'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('media-image')));
    await tester.pumpAndSettle();
    expect(model.active, isTrue);
    await _open(tester, tester.getCenter(find.byKey(const ValueKey('media-image'))));
    await _openArrange(tester);
    await tester.tap(find.text('Bring to Front'));
    await tester.pumpAndSettle();
    expect(model.active, isFalse);
    expect(model.selected, isTrue);
    expect(_canvas(tester).childOrder, ['other', 'editor']);
    await _open(tester, tester.getCenter(find.byKey(const ValueKey('media-image'))));
    expect(find.text('Arrange'), findsOneWidget);
    expect(model.active, isFalse);
    expect(model.focusNode.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(model.active, isFalse);
  });

  testWidgets('unknown layout sizes disable overlap commands but allow ends', (tester) async {
    var document = _document();
    document = document.withElements((elements) => elements.add(_text('unknown', const Offset(100000, 100000))));
    await pumpCanvas(tester, TestLibraryStore(document));
    final canvas = _canvas(tester);
    final info = canvas.getInfo('unknown');
    canvas
      ..removeChild('unknown')
      ..addChild(info.gsPosition, info.child, id: 'unknown');
    expect(canvas.getInfo('unknown').childSize, isNull);
    await _open(tester, const Offset(375, 375));
    await _openArrange(tester);
    expect(_button(tester, 'Bring Forward').onPressed, isNull);
    expect(_button(tester, 'Bring to Front').onPressed, isNotNull);
    await tester.tap(find.text('Bring to Front'));
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, ['a', 'b', 'c', 'unknown', 'd']);
  });

  testWidgets('unknown size disables Backward shortcut without affecting Send to Back', (tester) async {
    var document = _document();
    document = document.withElements((elements) => elements.add(_text('unknown', const Offset(100000, 100000))));
    final store = TestLibraryStore(document);
    await pumpCanvas(tester, store);
    final canvas = _canvas(tester);
    final info = canvas.getInfo('unknown');
    canvas
      ..removeChild('unknown')
      ..addChild(info.gsPosition, info.child, id: 'unknown')
      ..sendToBack(['unknown']);
    _models(tester)['a']!.setSelected(value: true);
    await _shortcut(tester, LogicalKeyboardKey.bracketLeft);
    expect(canvas.childOrder, ['unknown', 'a', 'b', 'c', 'd']);
    expect(store.persisted, isNull);
    await _open(tester, const Offset(305, 305));
    await _openArrange(tester);
    expect(_button(tester, 'Send Backward').onPressed, isNull);
    expect(_button(tester, 'Send to Back').onPressed, isNotNull);
    await tester.tap(find.text('Send to Back'));
    await tester.pumpAndSettle();
    expect(canvas.childOrder, ['a', 'unknown', 'b', 'c', 'd']);
  });

  testWidgets('overlap steps skip distant objects; no-op does not save or consume redo', (tester) async {
    var document = _document();
    document = document.withElements(
      (elements) => elements[1] = (elements[1] as ShapeElementData).copyWith(position: const Offset(650, 450)),
    );
    final store = TestLibraryStore(document);
    await pumpCanvas(tester, store);
    _models(tester)['a']!.setSelected(value: true);
    await _shortcut(tester, LogicalKeyboardKey.bracketLeft);
    await pumpPastSave(tester);
    expect(store.persisted, isNull);
    await _shortcut(tester, LogicalKeyboardKey.bracketRight);
    expect(_canvas(tester).childOrder, ['b', 'c', 'a', 'd']);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    _models(tester)['a']!.setSelected(value: true);
    await _shortcut(tester, LogicalKeyboardKey.bracketLeft, shift: true);
    await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(_canvas(tester).childOrder, ['b', 'c', 'a', 'd']);
  });

  testWidgets('rotated object menu stays in screen coordinates under zoom near edges', (tester) async {
    var document = _editorDocument('code');
    document = document.withElements(
      (elements) => elements[0] = (elements.first as CodeElementData).copyWith(
        position: const Offset(200, 140),
        rotation: math.pi / 4,
      ),
    );
    await pumpCanvas(tester, TestLibraryStore(document));
    _canvas(tester).updateScalebyDelta(0.5);
    await tester.pump();
    await _open(tester, tester.getCenter(find.byKey(const ValueKey('code-block-surface'))));
    final rect = tester.getRect(find.byType(SubmenuButton));
    expect(rect.width, greaterThan(rect.height));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));
    await _openArrange(tester);
    for (final label in ['Bring Forward', 'Send Backward', 'Bring to Front', 'Send to Back']) {
      final bounds = tester.getRect(find.text(label));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(800));
      expect(bounds.bottom, lessThanOrEqualTo(600));
    }
  });

  testWidgets('navigation, tools, file picker, and disposal close menus', (tester) async {
    final store = TestLibraryStore(_document());
    await pumpCanvas(tester, store);
    await _open(tester, const Offset(305, 305));
    _canvas(tester).updateScalebyDelta(0.1);
    await tester.pumpAndSettle();
    expect(find.text('Arrange'), findsNothing);
    await _open(tester, _canvas(tester).getInfo('a').ssPosition + const Offset(5, 5));
    tester.widget<ToolbarButton>(find.byKey(const ValueKey('toolbar-draw'))).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Arrange'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('toolbar-draw')));
    await tester.pumpAndSettle();
    await _open(tester, _canvas(tester).getInfo('a').ssPosition + const Offset(5, 5));
    tester.widget<CanvasTitle>(find.byType(CanvasTitle)).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Arrange'), findsNothing);
    expect(find.byType(CanvasFilePicker), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _open(tester, _canvas(tester).getInfo('a').ssPosition + const Offset(5, 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('target deletion and document replacement close menus', (tester) async {
    await pumpCanvas(tester, TestLibraryStore(_document()));
    await tester.tapAt(const Offset(305, 305));
    await tester.pumpAndSettle();
    expect(_models(tester)['a']!.active, isTrue);
    final controls = tester.widget<ElementTransformControls>(find.byType(ElementTransformControls));
    await _open(tester, const Offset(305, 305));
    controls.onDelete();
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, isNot(contains('a')));
    expect(find.text('Arrange'), findsNothing);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    await _open(tester, _canvas(tester).getInfo('a').ssPosition + const Offset(5, 5));
    tester.widget<CanvasTitle>(find.byType(CanvasTitle)).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New canvas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fresh');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_canvas(tester).childOrder, isEmpty);
    expect(find.text('Arrange'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('pen and arrow interactions preserve stacking order', (
    tester,
  ) async {
    await SharedPreferencesAsync().remove(PreferencesLibraryStore.libraryKey);
    final document = CanvasDocument(
      background: CanvasBackgroundKind.plain,
      elements: [
        PenElementData(
          autoArrange: false,
          id: 'pen',
          position: const Offset(100, 250),
          size: const Size(100, 30),
          hitSlop: 6,
          color: const Color(0xff000000),
          width: 3,
          points: const [
            PenPointData(Offset(0, 15), pressure: 0.5),
            PenPointData(Offset(100, 15), pressure: 0.5),
          ],
        ),
        ArrowElementData(
          autoArrange: false,
          id: 'arrow',
          start: const Offset(300, 250),
          controls: const [Offset(380, 235)],
          end: const Offset(460, 250),
          color: const Color(0xff000000),
          strokeStyle: ArrowStrokeStyle.solid,
          strokeWidth: 2,
        ),
      ],
    );
    await SharedPreferencesAsync().setString(
      PreferencesLibraryStore.libraryKey,
      jsonEncode(CanvasLibrary.initial(document).toJson()),
    );
    await tester.pumpWidget(const ElseplaneApp());
    await tester.pump();
    await tester.pump();

    final penFinder = find.byType(PenElementView);
    final arrowFinder = find.byType(ArrowElementView);
    final pen = tester.widget<PenElementView>(penFinder).resources;
    final arrow = canvasElement(tester, tester.widget<ArrowElementView>(arrowFinder).data);
    List<String> elementIds() => tester
        .widget<LazyCanvas>(find.byType(LazyCanvas))
        .controller
        .widgetsWithScreenPositions()
        .map((child) => child.id)
        .toList();

    expect(elementIds(), ['pen', 'arrow']);

    await tester.tapAt(tester.getCenter(penFinder));
    await tester.pump();
    expect(elementIds(), ['pen', 'arrow']);
    expect(pen.active, isFalse);
    expect(pen.selected, isFalse);
    expect(find.byKey(const ValueKey('pen-block-handle')), findsNothing);
    expect(find.byKey(const ValueKey('pen-block-delete-control')), findsNothing);
    expect(find.byKey(const ValueKey('pen-block-rotate-control')), findsNothing);

    final penPosition = tester.getTopLeft(penFinder);
    const penDelta = Offset(32, 18);
    await tester.drag(penFinder, penDelta, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(tester.getTopLeft(penFinder), penPosition + penDelta);
    expect(pen.active, isFalse);
    expect(pen.selected, isFalse);

    final arrowStart =
        tester.getTopLeft(arrowFinder) +
        Offset(
          arrow.start.dx - arrow.bounds.left,
          arrow.start.dy - arrow.bounds.top,
        );
    await tester.tapAt(arrowStart);
    await tester.pump();
    expect(elementIds(), ['pen', 'arrow']);
    expect(pen.active, isFalse);
    expect(arrow.active, isTrue);
    expect(arrow.selected, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tapAt(tester.getCenter(penFinder));
    await tester.pump();
    expect(elementIds(), ['pen', 'arrow']);
    expect(pen.selected, isTrue);

    await tester.tapAt(arrowStart);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(elementIds(), ['pen', 'arrow']);
    expect(arrow.selected, isFalse);

    await tester.pump(const Duration(milliseconds: 320));
    final saved = (await PreferencesLibraryStore().load())!.current.document!;
    expect(saved.elements.map((element) => element.id), ['pen', 'arrow']);
  });
}

// ---------- Helpers ----------

class _DelayedAttachmentStore extends TestAttachmentStore {
  final resume = Completer<void>();

  @override
  Future<void> write(String path, Uint8List bytes) async {
    await resume.future;
    await super.write(path, bytes);
  }
}

Future<void> _promoteOther(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.tapAt(const Offset(555, 405));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(_canvas(tester).childOrder, ['editor', 'other']);
}

Offset _activeEditorHitPoint(WidgetTester tester, String kind) => switch (kind) {
  'text' => tester.getCenter(find.byKey(const ValueKey('text-markdown-editor'))),
  'title' => tester.getCenter(find.byKey(const ValueKey('code-title-input'))),
  _ => _autoHitPoint(tester, kind),
};

CanvasDocument _autoDocument(String kind) {
  final document = kind == 'shape'
      ? (_document().withElements((elements) => elements.removeRange(2, 4)))
      : _editorDocument(kind);
  final elements = document.elements.toList();
  if (kind == 'pen') {
    elements[0] = PenElementData(
      id: 'editor',
      position: const Offset(150, 250),
      size: const Size(160, 30),
      hitSlop: 6,
      points: const [PenPointData(Offset(0, 15), pressure: 0.5), PenPointData(Offset(160, 15), pressure: 0.5)],
      color: const Color(0xff000000),
      width: 3,
    );
  } else if (kind == 'arrow') {
    elements[0] = ArrowElementData(
      id: 'editor',
      start: const Offset(150, 250),
      controls: const [Offset(230, 235)],
      end: const Offset(310, 250),
      color: const Color(0xff000000),
      strokeStyle: ArrowStrokeStyle.solid,
      strokeWidth: 2,
    );
  }
  final target = elements.first.copyWith(autoArrange: true);
  elements[0] = target is CodeElementData ? target.copyWith(size: const Size(300, 240)) : target;
  return document.copyWith(elements: elements);
}

Offset _autoHitPoint(WidgetTester tester, String kind) => switch (kind) {
  'shape' => const Offset(305, 305),
  'pen' => tester.getCenter(find.byType(PenElementView)),
  'arrow' => const Offset(150, 250),
  _ => tester.getCenter(
    find.byKey(
      ValueKey(switch (kind) {
        'text' => 'text-markdown-preview',
        'title' => 'code-title-text',
        'media' => 'media-url-field',
        _ => 'code-block-preview-surface',
      }),
    ),
  ),
};

LazyCanvasController _canvas(WidgetTester tester) => tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;

Map<String, ElementFixture<ShapeElementData>> _models(WidgetTester tester) => {
  for (final widget in tester.widgetList<ShapeElementView>(find.byType(ShapeElementView)))
    widget.data.id: canvasElement(tester, widget.data),
};

List<String> _order(CanvasDocument document) => document.elements.map((element) => element.id).toList();

MenuItemButton _button(WidgetTester tester, String label) => tester.widget<MenuItemButton>(
  find.ancestor(of: find.text(label), matching: find.byType(MenuItemButton)),
);

Future<void> _open(WidgetTester tester, Offset position, {Offset jitter = Offset.zero}) async {
  final click = await tester.startGesture(position, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
  if (jitter != Offset.zero) await click.moveBy(jitter);
  await click.up();
  await tester.pumpAndSettle();
}

Future<void> _openArrange(WidgetTester tester) async {
  Focus.of(tester.element(find.text('Arrange'))).requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.pumpAndSettle();
}

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  TargetPlatform platform = TargetPlatform.linux,
  bool shift = false,
  bool repeat = false,
}) async {
  final modifier = platform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final physicalKey = switch (key) {
    LogicalKeyboardKey.braceLeft => PhysicalKeyboardKey.bracketLeft,
    LogicalKeyboardKey.braceRight => PhysicalKeyboardKey.bracketRight,
    _ => null,
  };
  await tester.sendKeyDownEvent(key, physicalKey: physicalKey);
  if (repeat) await tester.sendKeyRepeatEvent(key, physicalKey: physicalKey);
  await tester.sendKeyUpEvent(key, physicalKey: physicalKey);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

CanvasDocument _document({bool auto = false}) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    for (var index = 0; index < 4; index++)
      ShapeElementData(
        autoArrange: auto,
        id: ['a', 'b', 'c', 'd'][index],
        kind: ShapeKind.rectangle,
        position: Offset(300 + index * 25, 300 + index * 25),
        size: const Size(140, 120),
        strokeColor: const Color(0xff000000),
        fillColor: const Color(0xffffffff),
        strokeWidth: 2,
      ),
  ],
);

TextElementData _text(String id, Offset position) => TextElementData(
  autoArrange: false,
  id: id,
  position: position,
  width: 280,
  height: null,
  markdown: 'contents',
  style: const TextNodeStyle(fontFamily: 'Inter', color: Color(0xff201C1A)),
);

CanvasDocument _editorDocument(String editor) => CanvasDocument(
  background: CanvasBackgroundKind.plain,
  elements: [
    if (editor == 'text')
      _text('editor', const Offset(150, 230))
    else if (editor == 'media')
      MediaElementData(autoArrange: false, id: 'editor', position: const Offset(150, 230), width: 280, url: '')
    else
      CodeElementData(
        autoArrange: false,
        id: 'editor',
        position: const Offset(150, 230),
        size: const Size(300, 240),
        language: CodeLanguage.plainText,
        source: 'contents',
        title: 'Title',
        showLineNumbers: false,
      ),
    ShapeElementData(
      autoArrange: false,
      id: 'other',
      kind: ShapeKind.rectangle,
      position: const Offset(550, 400),
      size: const Size(80, 80),
      strokeColor: const Color(0xff000000),
      fillColor: const Color(0xffffffff),
      strokeWidth: 2,
    ),
  ],
);

// ---------- Test helpers ----------
