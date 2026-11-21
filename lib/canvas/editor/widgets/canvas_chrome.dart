// Owns responsive placement of the canvas's floating controls.
// Used by the editor above the interactive canvas surface.

import 'dart:math' as math;

import 'package:elseplane/canvas/editor/widgets/tool_options.dart';
import 'package:elseplane/library/widgets/canvas_title.dart';
import 'package:flutter/material.dart';

// ---------- Canvas chrome ----------

class CanvasChrome extends StatelessWidget {
  // ---------- Construction ----------

  const CanvasChrome({
    required this.title,
    required this.toolbar,
    required this.settingsButton,
    required this.toolOptions,
    this.notification,
    super.key,
  });

  final CanvasTitle title;
  final Widget toolbar;
  final Widget settingsButton;
  final Widget? toolOptions;
  final Widget? notification;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(_ChromeLayout.gap),
      child: CustomMultiChildLayout(
        delegate: _ChromeLayout(
          minimumTitleWidth: title.collapsedWidthOf(context),
        ),
        children: [
          LayoutId(
            id: _Control.toolbar,
            child: toolbar,
          ),
          LayoutId(
            id: _Control.title,
            child: Align(
              alignment: Alignment.topLeft,
              child: title.indicator != null
                  ? title
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: title,
                    ),
            ),
          ),
          LayoutId(id: _Control.settings, child: settingsButton),
          LayoutId(
            id: _Control.options,
            child: ToolOptions(child: toolOptions),
          ),
          LayoutId(
            id: _Control.notification,
            child: notification ?? const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}

// ---------- Layout ----------

enum _Control { toolbar, title, settings, options, notification }

/// Places controls using their natural sizes, including Flutter density.
/// Keeps title and settings clear of the toolbar and its wrapped rows.
class _ChromeLayout extends MultiChildLayoutDelegate {
  _ChromeLayout({required this.minimumTitleWidth});

  static const gap = 12.0;
  static const notificationMaxWidth = 380.0;

  final double minimumTitleWidth;

  @override
  void performLayout(Size size) {
    final toolbar = layoutChild(_Control.toolbar, BoxConstraints.loose(size));
    positionChild(_Control.toolbar, Offset((size.width - toolbar.width) / 2, 0));

    final settings = layoutChild(_Control.settings, BoxConstraints.loose(size));
    final sideWidth = (size.width - toolbar.width) / 2 - gap;
    final titleBelow = sideWidth < minimumTitleWidth;
    final settingsBelow = sideWidth < settings.width;
    final lowerTop = toolbar.height + gap;
    final settingsTop = settingsBelow ? lowerTop : 0.0;
    positionChild(_Control.settings, Offset(size.width - settings.width, settingsTop));

    final titleWidth = math.max<double>(
      0,
      titleBelow ? size.width - (settingsBelow ? settings.width : ToolOptions.outerWidth) - gap : sideWidth,
    );
    final titleTop = titleBelow ? lowerTop : 0.0;
    final title = layoutChild(_Control.title, BoxConstraints.tightFor(width: titleWidth));
    positionChild(_Control.title, Offset(0, titleTop));

    final trayWidth = math.min(notificationMaxWidth, size.width);
    var notificationTop = titleTop + title.height;
    if (trayWidth > (size.width - toolbar.width) / 2) {
      notificationTop = math.max(notificationTop, toolbar.height);
    }
    if (trayWidth > size.width - settings.width) {
      notificationTop = math.max(notificationTop, settingsTop + settings.height);
    }
    notificationTop += gap;
    final notification = layoutChild(
      _Control.notification,
      BoxConstraints(
        maxWidth: trayWidth,
        maxHeight: math.max<double>(0, size.height - notificationTop),
      ),
    );
    positionChild(_Control.notification, Offset(0, notificationTop));

    final optionsBaseTop = math.max<double>(
      math.max(settingsTop + settings.height, toolbar.height),
      title.width + ToolOptions.outerWidth > size.width ? titleTop + title.height : 0,
    );
    final optionsColumnWidth = math.min(size.width, ToolOptions.outerWidth);
    final optionsOverlap = notification.height > 0 && notification.width + optionsColumnWidth > size.width;
    final optionsTop = math.max<double>(
      optionsBaseTop,
      optionsOverlap ? notificationTop + notification.height + gap : 0,
    );
    final options = layoutChild(
      _Control.options,
      BoxConstraints(
        maxWidth: math.min(size.width, ToolOptions.outerWidth),
        maxHeight: math.max(0, size.height - optionsTop),
      ),
    );
    positionChild(_Control.options, Offset(size.width - options.width, optionsTop));
  }

  @override
  bool shouldRelayout(_ChromeLayout oldDelegate) => minimumTitleWidth != oldDelegate.minimumTitleWidth;
}
