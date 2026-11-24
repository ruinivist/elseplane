// Owns compact spacing and balanced rows for the canvas's tool buttons.
// Used by canvas chrome without changing tool state or actions.

import 'dart:math' as math;

import 'package:elseplane/canvas/editor/widgets/toolbar_button.dart';
import 'package:elseplane/theme/sizes.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:flutter/widgets.dart';

// ---------- Canvas toolbar ----------

class CanvasToolbar extends StatelessWidget {
  // ---------- Construction ----------

  const CanvasToolbar({required this.buttonsBuilder, super.key});

  final List<Widget> Function({required bool compact}) buttonsBuilder;

  // ---------- Geometry ----------

  static const _compactHorizontalPadding = 10.0;

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final regularButtons = buttonsBuilder(compact: false);
      if (regularButtons.isEmpty) return const SizedBox.shrink();

      final regularSize = ToolbarButton.regularSizeOf(context);
      final compact = constraints.maxWidth < regularSize.width * regularButtons.length;
      final buttons = compact ? buttonsBuilder(compact: true) : regularButtons;
      final buttonWidth = compact
          ? BSizes.defaultIconButtonSize.width + _compactHorizontalPadding * 2
          : regularSize.width;
      final columns = math.max(1, (constraints.maxWidth / buttonWidth).floor());
      final rowCount = (buttons.length / columns).ceil();
      final perRow = buttons.length ~/ rowCount;
      final extra = buttons.length % rowCount;
      var start = 0;
      final rows = <Widget>[];
      for (var row = 0; row < rowCount; row++) {
        final end = start + perRow + (row < extra ? 1 : 0);
        rows.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final button in buttons.sublist(start, end))
                if (compact) SizedBox(width: buttonWidth, child: button) else button,
            ],
          ),
        );
        start = end;
      }

      return Surface(
        key: const ValueKey('toolbar-surface'),
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      );
    },
  );
}
