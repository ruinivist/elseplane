import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/editor/editor_session.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/ui/common/select.dart';
import 'package:material_ui/material_ui.dart';

final List<SelectOption<double>> _fontSizes = [
  for (final size in canvasFontSizes) SelectOption(value: size, label: size.toInt().toString()),
];

class CanvasFontSizeSelect extends StatelessWidget {
  const CanvasFontSizeSelect({required this.value, required this.onChanged, super.key});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Select<double>(value: value, options: _fontSizes, onChanged: onChanged);
}

final List<SelectOption<String>> _fontOptions = [
  for (final family in textNodeFontFamilies) SelectOption(value: family, label: family),
];

class CanvasFontSelect extends StatefulWidget {
  const CanvasFontSelect({
    required this.session,
    required this.id,
    required this.readFamily,
    required this.onLoaded,
    this.onChosen,
    this.onError,
    this.selectKey,
    this.loadFont = loadTextFont,
    super.key,
  });

  final EditorSession session;
  final String id;
  final String? Function(CanvasElementData?) readFamily;
  final ValueChanged<String> onLoaded;
  final VoidCallback? onChosen;
  final ValueChanged<String>? onError;
  final Key? selectKey;
  final Future<void> Function(String) loadFont;

  @override
  State<CanvasFontSelect> createState() => _CanvasFontSelectState();
}

typedef _FontRequest = ({Object token, String family, Object? lifetime, int restoration});

class _CanvasFontSelectState extends State<CanvasFontSelect> {
  _FontRequest? _request;

  bool _stillEligible(_FontRequest request) {
    final session = widget.session;
    return session.isLive &&
        session.activeId == widget.id &&
        session.restorationGeneration == request.restoration &&
        identical(session.elementLifetime(widget.id), request.lifetime) &&
        widget.readFamily(session.element(widget.id)) == request.family;
  }

  void _modelChanged() {
    final request = _request;
    if (request != null && !_stillEligible(request)) setState(() => _request = null);
  }

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_modelChanged);
  }

  @override
  void didUpdateWidget(CanvasFontSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session || oldWidget.id != widget.id) {
      oldWidget.session.removeListener(_modelChanged);
      widget.session.addListener(_modelChanged);
      _request = null;
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_modelChanged);
    super.dispose();
  }

  Future<void> _choose(String family) async {
    final session = widget.session;
    final previous = widget.readFamily(session.element(widget.id));
    if (_request != null || previous == null || !session.isLive || session.activeId != widget.id) return;
    widget.onChosen?.call();
    if (family == previous) return;
    final request = (
      token: Object(),
      family: previous,
      lifetime: session.elementLifetime(widget.id),
      restoration: session.restorationGeneration,
    );
    setState(() => _request = request);
    bool ownsRequest() => mounted && identical(_request?.token, request.token) && _stillEligible(request);
    try {
      await widget.loadFont(family);
    } on Object {
      if (mounted && ownsRequest()) {
        setState(() => _request = null);
        widget.onError?.call('Could not load font');
      }
      return;
    }
    if (!ownsRequest()) return;
    setState(() => _request = null);
    widget.onLoaded(family);
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.readFamily(widget.session.element(widget.id));
    if (family == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchableSelect<String>(
          key: widget.selectKey,
          value: family,
          options: textNodeFontFamilies.contains(family)
              ? _fontOptions
              : [SelectOption(value: family, label: family), ..._fontOptions],
          preferredValues: [family, defaultFontFamily],
          searchHint: 'Search fonts',
          onChanged: _request == null ? _choose : null,
        ),
        if (_request != null) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
      ],
    );
  }
}
