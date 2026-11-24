// Shows the shared workspace feedback cards in their viewport context.

import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/notifications.dart';
import 'package:elseplane/ui/previews/theme_preview.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

@Preview(
  name: 'Workspace notifications',
  size: Size(420, 260),
  theme: previewTheme,
  brightness: Brightness.light,
)
Widget notificationPreview() => const _NotificationPreview();

class _NotificationPreview extends StatefulWidget {
  const _NotificationPreview();

  @override
  State<_NotificationPreview> createState() => _NotificationPreviewState();
}

class _NotificationPreviewState extends State<_NotificationPreview> {
  final _notifications = NotificationController();

  @override
  void initState() {
    super.initState();
    _notifications
      ..show(
        'Canvas committed to GitHub.',
        severity: NotificationSeverity.success,
      )
      ..show('Could not save canvas', severity: NotificationSeverity.error);
  }

  @override
  void dispose() {
    _notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return ColoredBox(
      color: theme.colors.canvasBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Text('Workspace canvas', style: theme.typo.body),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CanvasTitle(path: ['Physics']),
                    const SizedBox(height: 12),
                    Flexible(child: NotificationHost(controller: _notifications)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
