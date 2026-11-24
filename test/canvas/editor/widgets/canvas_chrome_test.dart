// Verifies responsive controls against the original toolbar's geometry.
// Exercises title anchoring, wrapping, and pointer access in canvas chrome.

import 'dart:math' as math;

import 'package:elseplane/canvas/editor/widgets/canvas_chrome.dart';
import 'package:elseplane/canvas/editor/widgets/canvas_toolbar.dart';
import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:elseplane/ui/common/surface_icon_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// ---------- Tests ----------

void main() {
  for (final (width, titleBelow, actionBelow) in [
    (1000.0, false, false),
    (500.0, false, true),
    (200.0, true, true),
  ]) {
    testWidgets('the title stays fixed when Commit appears at width $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 520);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      var explorerOpens = 0;
      var commitOpens = 0;
      var touchOnly = false;
      late StateSetter update;
      final name = titleBelow ? 'A very long canvas name within a narrow editor' : 'Physics';
      const toolbarKey = ValueKey('toolbar');
      const settingsKey = ValueKey('settings');
      const optionsKey = ValueKey('options');
      final action = find.widgetWithText(TextButton, 'Commit');

      await tester.pumpWidget(
        MaterialApp(
          theme: starlessLightThemeData,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return CanvasChrome(
                  title: CanvasTitle(
                    path: ['Folder', name],
                    indicator: '*',
                    indicatorLabel: 'Uncommitted changes',
                    actionLabel: 'Commit',
                    showActionWithoutHover: touchOnly,
                    onAction: () => commitOpens++,
                    onPressed: () => explorerOpens++,
                  ),
                  toolbar: const SizedBox(key: toolbarKey, width: 170, height: 40),
                  settingsButton: const IconButton(key: settingsKey, onPressed: null, icon: Icon(Icons.settings)),
                  toolOptions: const SizedBox(key: optionsKey, height: 60),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final marker = find.text('*');
      final title = find.ancestor(of: marker, matching: find.byType(InkWell));
      final initialTitle = tester.getRect(title);
      final toolbar = tester.getRect(find.byKey(toolbarKey));
      expect(tester.renderObject<RenderParagraph>(find.text(name)).didExceedMaxLines, titleBelow);
      expect(initialTitle.top, titleBelow ? greaterThan(toolbar.bottom) : toolbar.top);
      expect(action, findsNothing);
      expect(marker.hitTestable(), findsOneWidget);
      expect(find.byTooltip('Uncommitted changes'), findsNothing);
      expect(find.bySemanticsLabel('Folder / $name, Uncommitted changes'), findsOneWidget);
      semantics.dispose();

      final gap = Offset(tester.getRect(marker).right + 4, initialTitle.center.dy);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: gap);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getRect(title), initialTitle);
      final actionBounds = tester.getRect(action);
      final path = find.text('Folder / $name');
      if (titleBelow) {
        final tooltip = find.ancestor(of: path, matching: find.byType(FadeTransition)).first;
        expect(tester.getRect(tooltip).top, greaterThan(actionBounds.bottom));
      } else {
        expect(path, findsNothing);
      }
      if (actionBelow) {
        expect(actionBounds.top, initialTitle.bottom);
        expect(actionBounds.left, initialTitle.left);
      } else {
        expect(actionBounds.left, initialTitle.right);
        expect(actionBounds.center.dy, initialTitle.center.dy);
      }
      for (final key in [toolbarKey, settingsKey, optionsKey]) {
        expect(actionBounds.overlaps(tester.getRect(find.byKey(key))), isFalse);
      }
      await tester.tapAt(gap, kind: PointerDeviceKind.mouse);
      expect(explorerOpens, 1);
      expect(commitOpens, 0);

      await mouse.moveTo(actionBounds.center);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      await tester.tap(action, kind: PointerDeviceKind.mouse);
      expect(explorerOpens, 1);
      expect(commitOpens, 1);
      await mouse.moveTo(const Offset(1, 500));
      await tester.pumpAndSettle();
      expect(action, findsNothing);
      expect(tester.getRect(title), initialTitle);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(explorerOpens, 2);
      expect(commitOpens, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(commitOpens, 2);
      expect(explorerOpens, 2);

      FocusManager.instance.primaryFocus?.unfocus();
      update(() => touchOnly = true);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getRect(title), initialTitle);
      await tester.tap(marker);
      expect(explorerOpens, 3);
      expect(commitOpens, 2);
      await tester.tap(action);
      expect(commitOpens, 3);
      expect(explorerOpens, 3);
      expect(tester.takeException(), isNull);
    });
  }

  for (final density in [VisualDensity.compact, VisualDensity.standard]) {
    testWidgets('preserves desktop sizing and compacts with left title at density $density', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final theme = starlessLightThemeData.copyWith(visualDensity: density);
      var selected = 0;
      var titleClicks = 0;
      var settingsClicks = 0;
      var canvasClicks = 0;
      var longTitle = false;
      var showOptions = true;
      late StateSetter update;

      List<Widget> buttons({required bool compact}) => [
        for (var i = 0; i < 7; i++)
          ToolbarButton(
            key: ValueKey('tool-$i'),
            compact: compact,
            selected: selected == i,
            onPressed: () => update(() => selected = i),
            child: const Icon(Icons.edit, size: 20),
          ),
      ];
      Widget settings() => SurfaceIconButton(
        key: const ValueKey('settings'),
        tooltip: 'Settings',
        onPressed: () => settingsClicks++,
        icon: const Icon(Icons.settings),
      );
      CanvasTitle title() => CanvasTitle(
        path: ['Folder', if (longTitle) 'A very long canvas title that needs horizontal scrolling' else 'Untitled'],
        onPressed: () => titleClicks++,
      );
      Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));

      // Measure the old row without imposing any button constraints.
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Surface(
                      key: const ValueKey('toolbar-surface'),
                      child: Row(mainAxisSize: MainAxisSize.min, children: buttons(compact: false)),
                    ),
                  ),
                ),
                Positioned(top: 12, right: 12, child: settings()),
                Positioned(top: 12, left: 12, child: title()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final originalToolbar = rect('toolbar-surface');
      final originalButtons = [for (var i = 0; i < 7; i++) rect('tool-$i')];
      final originalIconSize = tester.getSize(
        find.descendant(of: find.byKey(const ValueKey('tool-0')), matching: find.byType(Icon)),
      );
      final originalSettings = rect('settings');
      final originalTitle = tester.getRect(find.byType(CanvasTitle));
      final originalTitleLeft = originalTitle.left;
      final originalTextLeft = tester.getRect(find.text('Untitled')).left;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: ToolbarButton(
              key: const ValueKey('compact-reference'),
              selected: false,
              onPressed: () {},
              child: const Icon(Icons.edit, size: 20),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final compactSize = tester.getSize(find.byKey(const ValueKey('compact-reference')));

      Widget app({MediaQueryData media = const MediaQueryData()}) => MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: media.copyWith(size: tester.view.physicalSize),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => canvasClicks++),
                    ),
                    Positioned.fill(
                      child: CanvasChrome(
                        title: title(),
                        toolbar: CanvasToolbar(buttonsBuilder: buttons),
                        settingsButton: settings(),
                        toolOptions: showOptions
                            ? const SizedBox(key: ValueKey('options'), height: 1000, child: Text('Options'))
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final titleViewport = find.ancestor(of: find.byType(CanvasTitle), matching: find.byType(SingleChildScrollView));
      tester.view.physicalSize = const Size(488, 700);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final titleBoundsBefore = tester.getRect(titleViewport);
      expect(titleBoundsBefore.width, originalTitle.width);
      await tester.tapAt(
        Offset(titleBoundsBefore.right + 10, titleBoundsBefore.center.dy),
      );
      expect(canvasClicks, 1);
      canvasClicks = 0;
      final compactPitch = rect('tool-1').center.dx - rect('tool-0').center.dx;
      expect(compactPitch, greaterThan(compactSize.width));
      final fitWidth = originalToolbar.width + originalTitle.width * 2 + originalTitleLeft * 4;
      final widths = [
        1200.0,
        fitWidth + 1,
        fitWidth,
        fitWidth - 1,
        originalToolbar.width + originalTitleLeft * 2 + 1,
        originalToolbar.width + originalTitleLeft * 2,
        originalToolbar.width + originalTitleLeft * 2 - 1,
        compactPitch * originalButtons.length + originalTitleLeft * 2 + 1,
        compactPitch * originalButtons.length + originalTitleLeft * 2,
        compactPitch * originalButtons.length + originalTitleLeft * 2 - 1,
        980.0,
        900.0,
        800.0,
        745.0,
        708.0,
        649.0,
        589.0,
        550.0,
        488.0,
        400.0,
        320.0,
        280.0,
        200.0,
      ];
      for (final width in widths) {
        tester.view.physicalSize = Size(width, 700);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        final toolbar = rect('toolbar-surface');
        final titleBounds = tester.getRect(titleViewport);
        final settingsBounds = rect('settings');
        expect(titleBounds.left, originalTitleLeft, reason: 'title viewport at $width');
        final nameFits = toolbar.left - originalTitleLeft * 2 >= originalTitle.width;
        expect(titleBounds.top, nameFits ? toolbar.top : greaterThan(toolbar.bottom), reason: 'title row at $width');
        if (titleBounds.width >= originalTitle.width) {
          expect(tester.getRect(find.byType(CanvasTitle)).left, originalTitleLeft, reason: 'title at $width');
          expect(tester.getRect(find.text('Untitled')).left, originalTextLeft);
        }
        expect(toolbar.center.dx, width / 2);
        expect(toolbar.overlaps(titleBounds), isFalse);
        expect(toolbar.overlaps(settingsBounds), isFalse);
        expect(titleBounds.overlaps(settingsBounds), isFalse);
        expect(settingsBounds.size, originalSettings.size);
        for (var i = 0; i < 7; i++) {
          final compact = tester.widget<ToolbarButton>(find.byKey(ValueKey('tool-$i'))).compact;
          expect(
            rect('tool-$i').size,
            compact ? Size(compactPitch, compactSize.height) : originalButtons[i].size,
            reason: 'tool $i at $width',
          );
          final icon = find.descendant(of: find.byKey(ValueKey('tool-$i')), matching: find.byType(Icon));
          expect(
            tester.getSize(icon),
            originalIconSize,
          );
          expect(find.byKey(ValueKey('tool-$i')).hitTestable(), findsOneWidget);
        }
        if (width == widths.first) {
          expect(toolbar, originalToolbar);
          expect(settingsBounds, originalSettings);
          for (var i = 0; i < 7; i++) {
            expect(rect('tool-$i'), originalButtons[i]);
          }
        }
        if (width == 488) {
          expect(rect('tool-6').top, rect('tool-0').top);
          expect(toolbar.width, lessThan(originalToolbar.width));
        }
        if (width == 320 || width == 280) {
          expect(rect('tool-3').top, rect('tool-0').top);
          expect(rect('tool-4').top, greaterThan(rect('tool-0').top));
          expect(rect('tool-6').top, rect('tool-4').top);
          final lastRow = Rect.fromLTRB(
            rect('tool-4').left,
            rect('tool-4').top,
            rect('tool-6').right,
            rect('tool-6').bottom,
          );
          expect(lastRow.center.dx, toolbar.center.dx);
          expect(titleBounds.top, greaterThan(toolbar.bottom));
          expect(settingsBounds.top, titleBounds.top);
        }
        final optionsScroll = find.ancestor(
          of: find.byKey(const ValueKey('options')),
          matching: find.byType(SingleChildScrollView),
        );
        final panel = tester.getRect(optionsScroll);
        expect(panel.top, greaterThan(settingsBounds.bottom));
        expect(panel.overlaps(toolbar), isFalse);
        expect(panel.overlaps(titleBounds), isFalse);
        expect(panel.bottom, lessThanOrEqualTo(700));
        await tester.tap(find.text('Untitled'));
        await tester.tap(find.byKey(const ValueKey('settings')));
        await tester.tap(find.byKey(const ValueKey('tool-6')));
        await tester.pump();
        expect(tester.widget<ToolbarButton>(find.byKey(const ValueKey('tool-6'))).selected, isTrue);
        await tester.tapAt(Offset(width - 2, 680));
        await tester.drag(optionsScroll, const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(titleClicks, widths.length);
      expect(settingsClicks, widths.length);
      expect(canvasClicks, widths.length);

      tester.view.physicalSize = Size(fitWidth + 1, 700);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final titleAllocation = find.ancestor(of: find.byType(CanvasTitle), matching: find.byType(Align)).first;
      final topTitleBounds = tester.getRect(titleAllocation);
      expect(topTitleBounds.top, rect('toolbar-surface').top);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(titleViewport));
      await tester.pumpAndSettle();
      expect(tester.getRect(titleAllocation), topTitleBounds);
      expect(rect('toolbar-surface').overlaps(tester.getRect(titleViewport)), isFalse);
      expect(find.byKey(const ValueKey('tool-0')).hitTestable(), findsOneWidget);
      await tester.tap(find.text('Untitled'));
      expect(titleClicks, widths.length + 1);
      final titleScroll = tester.state<ScrollableState>(
        find.descendant(of: titleViewport, matching: find.byType(Scrollable)),
      );
      expect(titleScroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(titleViewport, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(titleScroll.position.pixels, greaterThan(0));
      expect(tester.getRect(titleAllocation), topTitleBounds);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();

      update(() => longTitle = true);
      await tester.pumpAndSettle();
      expect(tester.getRect(titleViewport).top, greaterThan(rect('toolbar-surface').bottom));
      update(() => longTitle = false);
      await tester.pumpAndSettle();
      expect(tester.getRect(titleViewport).top, rect('toolbar-surface').top);

      await tester.pumpWidget(
        app(
          media: const MediaQueryData(
            textScaler: TextScaler.linear(1.5),
            boldText: true,
            letterSpacingOverride: 1,
            wordSpacingOverride: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(titleViewport).top, greaterThan(rect('toolbar-surface').bottom));
      update(() => longTitle = true);
      await tester.pumpAndSettle();
      expect(
        title().collapsedWidthOf(tester.element(find.byType(CanvasChrome))),
        closeTo(tester.getSize(find.byType(CanvasTitle)).width, 0.001),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final beforeHover = tester.getRect(titleAllocation);
      await mouse.moveTo(tester.getCenter(titleViewport));
      await tester.pumpAndSettle();
      expect(tester.getRect(titleAllocation), beforeHover);
      expect(rect('toolbar-surface').overlaps(tester.getRect(titleViewport)), isFalse);
      await mouse.moveTo(Offset.zero);
      update(() => showOptions = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getRect(titleAllocation), beforeHover);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('options')), findsNothing);
      update(() => showOptions = true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('options')), findsOneWidget);

      tester.view.physicalSize = Size(compactPitch * 3 + originalTitleLeft * 2, 400);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(rect('tool-0').top, rect('tool-2').top);
      expect(rect('tool-3').top, greaterThan(rect('tool-2').top));
      expect(rect('tool-3').top, rect('tool-4').top);
      expect(rect('tool-5').top, greaterThan(rect('tool-4').top));
      expect(rect('tool-5').top, rect('tool-6').top);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(320, 400);
      await tester.pumpWidget(app(media: const MediaQueryData(padding: EdgeInsets.fromLTRB(10, 24, 18, 20))));
      await tester.pumpAndSettle();
      expect(rect('toolbar-surface').top, greaterThanOrEqualTo(24));
      expect(rect('toolbar-surface').right, lessThanOrEqualTo(302));
      expect(tester.getRect(titleViewport).left, greaterThanOrEqualTo(10));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('anchors notifications below top controls without covering options', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: starlessLightThemeData,
        home: const Scaffold(
          body: CanvasChrome(
            title: CanvasTitle(path: ['Physics']),
            toolbar: SizedBox(key: ValueKey('toolbar'), width: 700, height: 64),
            settingsButton: SizedBox(key: ValueKey('settings'), width: 40, height: 40),
            toolOptions: SizedBox(key: ValueKey('notification-options'), height: 300),
            notification: SizedBox(key: ValueKey('notification-slot'), width: 380, height: 56),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slot = tester.getRect(find.byKey(const ValueKey('notification-slot')));
    final title = tester.getRect(find.byType(CanvasTitle));
    final toolbar = tester.getRect(find.byKey(const ValueKey('toolbar')));
    final settings = tester.getRect(find.byKey(const ValueKey('settings')));
    final options = tester.getRect(
      find.ancestor(
        of: find.byKey(const ValueKey('notification-options')),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(slot.left, 12);
    expect(slot.top, math.max(title.bottom, math.max(toolbar.bottom, settings.bottom)) + 12);
    expect(slot.right, lessThan(options.left));
    expect(options.top, greaterThanOrEqualTo(toolbar.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrapped title positions tray and options restore when empty', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(220, 420);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var showNotification = false;
    late StateSetter update;

    Widget app() => MaterialApp(
      theme: starlessLightThemeData,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return CanvasChrome(
              title: CanvasTitle(
                path: const ['Physics'],
                indicator: '*',
                indicatorLabel: 'Uncommitted changes',
                actionLabel: 'Commit',
                showActionWithoutHover: true,
                onAction: () {},
              ),
              toolbar: const SizedBox(key: ValueKey('wrapped-toolbar'), width: 160, height: 48),
              settingsButton: const SizedBox(key: ValueKey('wrapped-settings'), width: 40, height: 40),
              toolOptions: const SizedBox(key: ValueKey('wrapped-options'), height: 800),
              notification: showNotification
                  ? const SizedBox(key: ValueKey('wrapped-notification'), width: 196, height: 56)
                  : null,
            );
          },
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final options = find.ancestor(
      of: find.byKey(const ValueKey('wrapped-options')),
      matching: find.byType(SingleChildScrollView),
    );
    final originalOptionsTop = tester.getRect(options).top;
    final toolbar = tester.getRect(find.byKey(const ValueKey('wrapped-toolbar')));
    final title = tester.getRect(find.byType(CanvasTitle));
    expect(title.top, greaterThan(toolbar.bottom));
    expect(title.height, greaterThan(40));

    update(() => showNotification = true);
    await tester.pumpAndSettle();
    final slot = tester.getRect(find.byKey(const ValueKey('wrapped-notification')));
    expect(slot.left, 12);
    expect(slot.top, title.bottom + 12);
    expect(tester.getRect(options).top, greaterThanOrEqualTo(slot.bottom + 12));

    update(() => showNotification = false);
    await tester.pumpAndSettle();
    expect(tester.getRect(options).top, originalOptionsTop);
    expect(tester.takeException(), isNull);
  });
}
