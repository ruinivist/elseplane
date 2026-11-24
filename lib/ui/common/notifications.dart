// Owns short-lived workspace feedback and its presentation.
// Used by Workspace to report outcomes without coupling shared UI to features.

import 'dart:async';
import 'dart:math' as math;

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/material.dart';

// ---------- Notification state ----------

enum NotificationSeverity { info, success, warning, error }

class NotificationAction {
  const NotificationAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

class NotificationController extends ChangeNotifier {
  final List<_NotificationEvent> _events = [];
  var _nextId = 0;
  var _covered = false;
  var _disposed = false;

  List<_NotificationItem> get _visibleItems => [
    for (final event in _events)
      if (event.visible && (event.progressVisible || event.completed || event.exiting))
        _NotificationItem(
          id: event.id,
          message: event.message,
          severity: event.severity,
          action: event.action,
          progress: event.progress && event.progressVisible,
          exiting: event.exiting,
        ),
  ];

  bool get hasVisibleCards => _visibleItems.isNotEmpty;

  NotificationOperation begin(String message) {
    if (_disposed) return NotificationOperation._(this, -1);
    final event = _NotificationEvent(
      id: _nextId++,
      message: message,
      severity: NotificationSeverity.info,
      progress: true,
    );
    _events.add(event);
    event.progressTimer = Timer(const Duration(milliseconds: 300), () {
      if (_disposed || event.completed) return;
      event.progressVisible = true;
      if (!event.closedProgress) {
        _promote();
        if (event.visible) notifyListeners();
      }
    });
    return NotificationOperation._(this, event.id);
  }

  void show(
    String message, {
    NotificationSeverity severity = NotificationSeverity.info,
    NotificationAction? action,
  }) {
    if (_disposed) return;
    _events.add(
      _NotificationEvent(
        id: _nextId++,
        message: message,
        severity: severity,
        action: action,
        completed: true,
      ),
    );
    _promote();
    notifyListeners();
  }

  void _setCovered({required bool covered}) {
    if (_disposed || covered == _covered) return;
    _covered = covered;
    _events.forEach(_syncExpiry);
  }

  void _setHovered(int id, {required bool hovered}) {
    final event = _event(id);
    if (event == null || event.hovered == hovered) return;
    event.hovered = hovered;
    _syncExpiry(event);
  }

  void _setFocused(int id, {required bool focused}) {
    final event = _event(id);
    if (event == null || event.focused == focused) return;
    event.focused = focused;
    _syncExpiry(event);
  }

  void _dismiss(int id) {
    final event = _event(id);
    if (event == null || event.exiting) return;
    if (event.progress && !event.completed) event.closedProgress = true;
    _exit(event);
  }

  void _finishExit(int id) {
    final event = _event(id);
    if (event == null || !event.exiting) return;
    event
      ..visible = false
      ..exiting = false;
    if (!event.progress || event.completed) _remove(event);
    _promote();
    notifyListeners();
  }

  void _complete(
    int id,
    String message, {
    required NotificationSeverity severity,
    NotificationAction? action,
  }) {
    final event = _event(id);
    if (_disposed || event == null || !event.progress || event.completed) return;
    event
      ..completed = true
      ..progress = false
      ..progressTimer?.cancel()
      ..progressTimer = null;

    if (event.closedProgress) {
      if (severity == NotificationSeverity.warning || severity == NotificationSeverity.error) {
        event
          ..message = message
          ..severity = severity
          ..action = action
          ..closedProgress = false
          ..exiting = false;
        if (event.visible) {
          _startExpiry(event);
        } else {
          _promote();
        }
        notifyListeners();
      } else if (!event.visible) {
        _remove(event);
      }
      return;
    }

    event
      ..message = message
      ..severity = severity
      ..action = action;
    if (event.visible) {
      _startExpiry(event);
    } else {
      _promote();
    }
    notifyListeners();
  }

  _NotificationEvent? _event(int id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  void _promote() {
    while (_events.where((event) => event.visible).length < 2) {
      final queued = _events
          .where((event) => !event.visible && !event.closedProgress && (!event.progress || event.progressVisible))
          .toList();
      if (queued.isEmpty) return;
      queued.sort((a, b) {
        final priority = _priority(b.severity).compareTo(_priority(a.severity));
        return priority != 0 ? priority : a.id.compareTo(b.id);
      });
      final event = queued.first..visible = true;
      if (event.completed) _startExpiry(event);
    }
  }

  int _priority(NotificationSeverity severity) =>
      severity == NotificationSeverity.warning || severity == NotificationSeverity.error ? 1 : 0;

  void _startExpiry(_NotificationEvent event) {
    if (event.remaining != null || !event.visible || event.exiting) return;
    final duration = event.action == null ? const Duration(seconds: 4) : const Duration(seconds: 10);
    if (event.severity == NotificationSeverity.warning || event.severity == NotificationSeverity.error) return;
    event.remaining = duration;
    _syncExpiry(event);
  }

  void _syncExpiry(_NotificationEvent event) {
    event.expiryTimer?.cancel();
    event.expiryTimer = null;
    if (event.remaining == null ||
        !event.visible ||
        event.exiting ||
        event.hovered ||
        event.focused ||
        _covered ||
        _disposed) {
      return;
    }
    event.expiryTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final remaining = event.remaining;
      if (remaining == null || _disposed) {
        timer.cancel();
        return;
      }
      final next = remaining - const Duration(milliseconds: 100);
      event.remaining = next;
      if (next <= Duration.zero) {
        timer.cancel();
        event.expiryTimer = null;
        _exit(event);
      }
    });
  }

  void _exit(_NotificationEvent event) {
    event
      ..exiting = true
      ..expiryTimer?.cancel()
      ..expiryTimer = null;
    notifyListeners();
  }

  void _remove(_NotificationEvent event) {
    event
      ..progressTimer?.cancel()
      ..expiryTimer?.cancel();
    _events.remove(event);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final event in _events) {
      event
        ..progressTimer?.cancel()
        ..expiryTimer?.cancel();
    }
    _events.clear();
    super.dispose();
  }
}

class NotificationOperation {
  const NotificationOperation._(this._controller, this._id);

  final NotificationController _controller;
  final int _id;

  void complete(
    String message, {
    NotificationSeverity severity = NotificationSeverity.success,
    NotificationAction? action,
  }) => _controller._complete(_id, message, severity: severity, action: action);
}

@immutable
class _NotificationItem {
  const _NotificationItem({
    required this.id,
    required this.message,
    required this.severity,
    required this.action,
    required this.progress,
    required this.exiting,
  });

  final int id;
  final String message;
  final NotificationSeverity severity;
  final NotificationAction? action;
  final bool progress;
  final bool exiting;
}

class _NotificationEvent {
  _NotificationEvent({
    required this.id,
    required this.message,
    required this.severity,
    this.action,
    this.progress = false,
    this.completed = false,
  });

  final int id;
  String message;
  NotificationSeverity severity;
  NotificationAction? action;
  bool progress;
  bool progressVisible = false;
  bool completed;
  bool visible = false;
  bool exiting = false;
  bool closedProgress = false;
  bool hovered = false;
  bool focused = false;
  Duration? remaining;
  Timer? progressTimer;
  Timer? expiryTimer;
}

// ---------- Presentation ----------

class NotificationHost extends StatefulWidget {
  const NotificationHost({required this.controller, super.key});

  final NotificationController controller;

  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost> {
  var _routeCurrent = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant NotificationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current == _routeCurrent) return;
    _routeCurrent = current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller._setCovered(covered: !current);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller._visibleItems;
    if (items.isEmpty) return const SizedBox.shrink();
    return ExcludeSemantics(
      excluding: !_routeCurrent,
      child: IgnorePointer(
        ignoring: !_routeCurrent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.constrainWidth(380);
            final maxHeight = math.min<double>(260, constraints.maxHeight * 0.36);
            return SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  hitTestBehavior: HitTestBehavior.translucent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < items.length; index++)
                        Padding(
                          key: ValueKey('notification-slot-${items[index].id}'),
                          padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
                          child: _NotificationCard(
                            item: items[index],
                            controller: widget.controller,
                            routeCurrent: _routeCurrent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.controller,
    required this.routeCurrent,
  });

  final _NotificationItem item;
  final NotificationController controller;
  final bool routeCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160);
    return Focus(
      key: ValueKey('notification-focus-${item.id}'),
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => controller._setFocused(item.id, focused: focused),
      child: MouseRegion(
        key: ValueKey('notification-mouse-${item.id}'),
        onEnter: (_) => controller._setHovered(item.id, hovered: true),
        onExit: (_) => controller._setHovered(item.id, hovered: false),
        child: IgnorePointer(
          ignoring: item.exiting || !routeCurrent,
          child: AnimatedOpacity(
            key: ValueKey('notification-card-${item.id}'),
            opacity: item.exiting ? 0 : 1,
            duration: duration,
            onEnd: () => controller._finishExit(item.id),
            child: Surface(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ExcludeSemantics(
                        child: item.progress
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colors.textMuted,
                                ),
                              )
                            : Icon(_icon(item.severity), size: 18, color: theme.colors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                item.message,
                                style: theme.typo.body.copyWith(color: theme.colors.textPrimary),
                              ),
                            ),
                          ),
                          if (item.action case final action?)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(onPressed: action.onPressed, child: Text(action.label)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss notification',
                      onPressed: () => controller._dismiss(item.id),
                      icon: const Icon(Icons.close, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _icon(NotificationSeverity severity) => switch (severity) {
    NotificationSeverity.info => Icons.info_outline,
    NotificationSeverity.success => Icons.check_circle_outline,
    NotificationSeverity.warning => Icons.warning_amber_outlined,
    NotificationSeverity.error => Icons.error_outline,
  };
}
