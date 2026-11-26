// Provides themed dialog surfaces and confirmation layouts.
// Used by application settings and canvas replacement or deletion prompts.

import 'package:elseplane/theme/theme.dart';
import 'package:elseplane/ui/common/surface.dart';
import 'package:material_ui/material_ui.dart';

Future<T?> showScaleDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _ScaleDialogRoute<T>(
      context: context,
      builder: builder,
      barrierColor:
          barrierColor ??
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    ),
  );
}

class _ScaleDialogRoute<T> extends DialogRoute<T> {
  _ScaleDialogRoute({
    required super.context,
    required super.builder,
    required super.barrierColor,
    required super.barrierDismissible,
    required super.themes,
    required super.traversalEdgeBehavior,
  });

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => ScaleTransition(
    scale: animation.drive(Tween<double>(begin: 0.94, end: 1).chain(CurveTween(curve: Curves.easeOut))),
    child: child,
  );
}

// ---------- Dialog shell ----------

class SurfaceDialog extends StatelessWidget {
  const SurfaceDialog({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.all(16),
    child: Surface(kind: SurfaceKind.dialog, child: child),
  );
}

// ---------- Confirmation ----------

class SurfaceConfirmationDialog extends StatelessWidget {
  const SurfaceConfirmationDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return SurfaceDialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        namesRoute: true,
                        child: DefaultTextStyle(style: theme.typo.title, child: title),
                      ),
                      const SizedBox(height: 16),
                      DefaultTextStyle(style: theme.typo.body, child: content),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: actions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
