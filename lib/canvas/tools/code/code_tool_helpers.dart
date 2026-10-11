// Provides the code tool's compact title, language, and settings controls.
// Used internally by code rendering and by the active-element settings panel.

part of 'code_tool.dart';

// ---------- Geometry ----------

const _codeTitleHeight = 34.0;
const _codeControlInset = 8.0;
const _codeEditorPadding = 10.0;
const _codeControlAnimationDuration = Duration(milliseconds: 220);

Widget _codeControlTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
      child: child,
    ),
  );
}

// ---------- Backgrounds ----------

Color _codeSurfaceColor(BColors colors, CodeBlockModel model) {
  if (model.selected) return colors.accentSoft;
  return model.background == BlockBackgroundKind.transparent ? Colors.transparent : colors.surface;
}

BorderSide _codeSurfaceBorder(BColors colors, CodeBlockModel model) {
  if (model.selected) return BorderSide(color: colors.accent, width: 2);
  if (model.background == BlockBackgroundKind.transparent && !model.active) return BorderSide.none;
  return BorderSide(
    color: colors.borderSubtle,
  );
}

// ---------- Title ----------

class _CodeTitleTab extends StatelessWidget {
  const _CodeTitleTab({
    required this.model,
    required this.editing,
  });

  final CodeBlockModel model;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    final colors = theme.colors;
    final style = theme.typo.body.copyWith(color: colors.textHeading);
    final border = _codeSurfaceBorder(colors, model);
    final borderRadius = BorderRadius.only(
      topLeft: theme.geo.radiusMedium.topLeft,
      topRight: theme.geo.radiusMedium.topRight,
    );
    return IntrinsicWidth(
      child: Stack(
        key: ValueKey(editing ? 'code-title-input-tab' : 'code-title-tab'),
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: -theme.geo.radiusMedium.topLeft.y,
            child: model.background == BlockBackgroundKind.glass
                ? GlassSurface(
                    key: ValueKey(editing ? 'code-title-input-tab-surface' : 'code-title-tab-surface'),
                    selected: model.selected,
                    borderRadius: borderRadius,
                    clipper: _CodeTitleSurfaceClipper(
                      theme.geo.radiusMedium.toRRect(const Offset(0, _codeTitleHeight) & model.size),
                    ),
                    child: const SizedBox.expand(),
                  )
                : ClipPath(
                    clipper: _CodeTitleSurfaceClipper(
                      theme.geo.radiusMedium.toRRect(const Offset(0, _codeTitleHeight) & model.size),
                    ),
                    child: Container(
                      key: ValueKey(editing ? 'code-title-input-tab-surface' : 'code-title-tab-surface'),
                      decoration: BoxDecoration(
                        color: _codeSurfaceColor(colors, model),
                        border: Border(top: border, left: border, right: border),
                        borderRadius: borderRadius,
                      ),
                    ),
                  ),
          ),
          Container(
            constraints: BoxConstraints(minWidth: 76, maxWidth: model.size.width),
            height: _codeTitleHeight,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.fromLTRB(12 + border.width, border.width, 12 + border.width, 0),
            child: Semantics(
              label: editing ? null : model.title,
              child: ExcludeSemantics(
                excluding: !editing,
                child: IgnorePointer(
                  ignoring: !editing,
                  child: TextFormField(
                    key: ValueKey(editing ? 'code-title-input' : 'code-title-text'),
                    contextMenuBuilder: null,
                    controller: model.titleController,
                    style: style,
                    cursorColor: colors.accent,
                    readOnly: !editing,
                    canRequestFocus: editing,
                    showCursor: editing,
                    enableInteractiveSelection: editing,
                    decoration: InputDecoration(
                      hintText: 'Untitled',
                      hintStyle: style.copyWith(color: colors.textMuted),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the extended title surface outside the body's rounded outline.
class _CodeTitleSurfaceClipper extends CustomClipper<Path> {
  const _CodeTitleSurfaceClipper(this.body);

  final RRect body;

  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.difference,
    Path()..addRect(Offset.zero & size),
    Path()..addRRect(body),
  );

  @override
  bool shouldReclip(_CodeTitleSurfaceClipper oldClipper) => body != oldClipper.body;
}

// ---------- Settings ----------

/// Presents line-number and background settings for the active code block.
class CodeToolSettings extends StatelessWidget {
  const CodeToolSettings({
    required this.model,
    required this.onChangeBoundary,
    super.key,
  });

  final CodeBlockModel model;
  final VoidCallback onChangeBoundary;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LabeledSwitch(
            key: const ValueKey('code-show-line-numbers'),
            label: 'Line numbers',
            value: model.showLineNumbers,
            onChanged: _setShowLineNumbers,
          ),
          const SizedBox(height: 10),
          Text('Background', style: theme.typo.label),
          const SizedBox(height: 6),
          Select<BlockBackgroundKind>(
            key: const ValueKey('code-background-select'),
            value: model.background,
            options: const [
              SelectOption(value: BlockBackgroundKind.transparent, label: 'Transparent'),
              SelectOption(value: BlockBackgroundKind.card, label: 'Card'),
              SelectOption(value: BlockBackgroundKind.glass, label: 'Glass'),
            ],
            onChanged: (background) {
              onChangeBoundary();
              model.background = background;
              onChangeBoundary();
            },
          ),
        ],
      ),
    );
  }

  void _setShowLineNumbers(bool value) {
    onChangeBoundary();
    model.showLineNumbers = value;
    onChangeBoundary();
  }
}
