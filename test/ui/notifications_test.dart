import 'package:elseplane/theme/starless.dart';
import 'package:elseplane/ui/common/notifications.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('fast completion shows only the result', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    notifications.begin('Saving canvas…').complete('Canvas saved.');
    await tester.pump();
    expect(find.text('Canvas saved.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    notifications.dispose();
  });

  testWidgets('progress result preserves its card and ignores duplicate completion', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    final operation = notifications.begin('Committing canvas…');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final card = find.byKey(const ValueKey('notification-card-0'));
    final mountedCard = tester.element(card);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    operation.complete('Canvas committed.');
    await tester.pump();
    expect(tester.element(card), same(mountedCard));
    expect(find.text('Canvas committed.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    operation.complete('Duplicate completion', severity: NotificationSeverity.error);
    await tester.pump();
    expect(find.text('Canvas committed.'), findsOneWidget);
    expect(find.text('Duplicate completion'), findsNothing);
    notifications.dispose();
  });

  testWidgets('completion after disposal is ignored', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    final operation = notifications.begin('Committing canvas…');
    notifications.dispose();
    operation.complete('Late result', severity: NotificationSeverity.error);
    await tester.pump();

    expect(find.text('Late result'), findsNothing);
  });

  testWidgets('empty host takes no space or pointer input', (tester) async {
    final notifications = NotificationController();
    var canvasTaps = 0;
    await _pumpHost(tester, notifications, onCanvasTap: () => canvasTaps++);

    final host = find.byType(NotificationHost);
    final emptyHost = find.descendant(of: host, matching: find.byType(SizedBox));
    expect(tester.getSize(emptyHost), Size.zero);
    await tester.tapAt(const Offset(60, 80));
    expect(canvasTaps, 1);

    notifications.show('Canvas saved.');
    await tester.pump();
    final hostLayout = find.descendant(of: host, matching: find.byType(IgnorePointer)).first;
    expect(tester.getSize(hostLayout).width, 380);
    expect(tester.getSize(hostLayout).height, greaterThan(0));
    notifications.dispose();
  });

  testWidgets('distinct events queue and urgent results use the next free slot first', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    notifications
      ..show('First notice')
      ..show('Second notice')
      ..show('Queued notice')
      ..show('First warning', severity: NotificationSeverity.warning)
      ..show('Second warning', severity: NotificationSeverity.error);
    await tester.pump();
    expect(find.byTooltip('Dismiss notification'), findsNWidgets(2));
    expect(find.text('First notice'), findsOneWidget);
    expect(find.text('Second notice'), findsOneWidget);
    expect(find.text('Queued notice'), findsNothing);

    await tester.tap(find.byTooltip('Dismiss notification').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byTooltip('Dismiss notification'), findsNWidgets(2));
    expect(find.text('First warning'), findsOneWidget);
    expect(find.text('Queued notice'), findsNothing);

    await tester.tap(find.byTooltip('Dismiss notification').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byTooltip('Dismiss notification'), findsNWidgets(2));
    expect(find.text('Second warning'), findsOneWidget);
    expect(find.text('Queued notice'), findsNothing);
    notifications.dispose();
  });

  testWidgets('visible success expiry pauses while hovered', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    notifications.show('Canvas saved.');
    await tester.pump();
    final card = find.byKey(const ValueKey('notification-card-0'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(card));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Canvas saved.'), findsOneWidget);

    await mouse.moveTo(const Offset(600, 460));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Canvas saved.'), findsNothing);
    notifications.dispose();
  });

  testWidgets('visible success expiry pauses while focused', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    final initialFocus = FocusManager.instance.primaryFocus;
    notifications.show('Canvas saved.');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(same(initialFocus)));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Canvas saved.'), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Canvas saved.'), findsNothing);
    notifications.dispose();
  });

  testWidgets('modal routes pause expiry and suppress card interaction', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    notifications.show('Canvas saved.');
    await tester.pump();
    final dialog = showDialog<void>(
      context: tester.element(find.byType(NotificationHost)),
      builder: (_) => const AlertDialog(content: Text('Modal')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Canvas saved.'), findsOneWidget);
    expect(find.byTooltip('Dismiss notification').hitTestable(), findsNothing);

    Navigator.of(tester.element(find.text('Modal'))).pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(find.text('Canvas saved.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Canvas saved.'), findsNothing);
    notifications.dispose();
  });

  testWidgets('closing progress does not cancel work or resurface success', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    final operation = notifications.begin('Saving canvas…');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(notifications.hasVisibleCards, isFalse);

    operation.complete('Canvas saved.');
    await tester.pump();
    expect(find.text('Canvas saved.'), findsNothing);
    expect(notifications.hasVisibleCards, isFalse);
    notifications.dispose();
  });

  testWidgets('closing progress allows a later warning to surface', (tester) async {
    final notifications = NotificationController();
    await _pumpHost(tester, notifications);

    final operation = notifications.begin('Saving canvas…');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    operation.complete('Could not save canvas', severity: NotificationSeverity.error);
    await tester.pump();
    expect(find.text('Could not save canvas'), findsOneWidget);
    expect(notifications.hasVisibleCards, isTrue);
    notifications.dispose();
  });

  testWidgets('notifications do not take focus, capture Escape, or block the canvas', (tester) async {
    final notifications = NotificationController();
    var canvasTaps = 0;
    await _pumpHost(tester, notifications, onCanvasTap: () => canvasTaps++);
    final initialFocus = FocusManager.instance.primaryFocus;

    notifications.show('Persistent warning', severity: NotificationSeverity.warning);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(initialFocus));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Persistent warning'), findsOneWidget);

    final card = find.byKey(const ValueKey('notification-card-0'));
    final cardRect = tester.getRect(card);
    expect(cardRect.left, 0);
    await tester.tapAt(cardRect.center);
    expect(canvasTaps, 0);
    await tester.tapAt(Offset(cardRect.right + 20, cardRect.top + 8));
    expect(canvasTaps, 1);
    await tester.tapAt(Offset(cardRect.left + 8, cardRect.bottom + 24));
    expect(canvasTaps, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(same(initialFocus)));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Persistent warning'), findsNothing);
    expect(canvasTaps, 2);
    notifications.dispose();
  });

  testWidgets('canvas receives taps in the gap between notification cards', (tester) async {
    final notifications = NotificationController();
    var canvasTaps = 0;
    await _pumpHost(tester, notifications, onCanvasTap: () => canvasTaps++);

    notifications
      ..show('First warning', severity: NotificationSeverity.warning)
      ..show('Second warning', severity: NotificationSeverity.warning);
    await tester.pump();

    final first = tester.getRect(find.byKey(const ValueKey('notification-card-0')));
    final second = tester.getRect(find.byKey(const ValueKey('notification-card-1')));
    expect(second.top - first.bottom, 8);
    expect(find.text('First warning'), findsOneWidget);
    expect(find.text('Second warning'), findsOneWidget);

    await tester.tapAt(Offset(first.left + 8, (first.bottom + second.top) / 2));
    expect(canvasTaps, 1);
    expect(find.text('First warning'), findsOneWidget);
    expect(find.text('Second warning'), findsOneWidget);
    notifications.dispose();
  });

  testWidgets('cards wrap within narrow and short viewports', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 220);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final notifications = NotificationController();
    await _pumpHost(tester, notifications, size: const Size(240, 220));

    notifications
      ..show(
        'A long notification message that must wrap rather than get clipped on a narrow display.',
        severity: NotificationSeverity.error,
      )
      ..show('Another warning that remains available by scrolling.', severity: NotificationSeverity.warning);
    await tester.pump();

    final hostLayout = find.descendant(of: find.byType(NotificationHost), matching: find.byType(IgnorePointer)).first;
    expect(tester.getSize(hostLayout).width, 240);
    expect(tester.getSize(hostLayout).height, lessThanOrEqualTo(220 * 0.36));
    expect(tester.getSize(find.byKey(const ValueKey('notification-card-0'))).width, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
    notifications.dispose();
  });
}

Future<void> _pumpHost(
  WidgetTester tester,
  NotificationController notifications, {
  Size size = const Size(640, 480),
  VoidCallback? onCanvasTap,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      theme: starlessLightThemeData,
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCanvasTap,
              ),
            ),
            Align(
              alignment: Alignment.topLeft,
              child: NotificationHost(controller: notifications),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}
