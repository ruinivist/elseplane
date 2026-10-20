// Renders Markdown, LaTeX, images, and links for text blocks.
// Used by the text tool whenever a text element is not being edited.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/tools/code/code_language.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------- Preview ----------

/// Renders styled Markdown and translates surface drags into canvas movement.
/// Used by the text tool for inactive text elements.
class TextMarkdownPreview extends StatefulWidget {
  const TextMarkdownPreview({
    required this.source,
    required this.style,
    required this.scrollController,
    required this.onEdit,
    required this.onMove,
    required this.attachmentStore,
    this.onInteract,
    super.key,
  });

  final String source;
  final TextNodeStyle style;
  final ScrollController? scrollController;
  final VoidCallback onEdit;
  final VoidCallback? onInteract;
  final ValueChanged<Offset> onMove;
  final AttachmentStore attachmentStore;

  @override
  State<TextMarkdownPreview> createState() => _TextMarkdownPreviewState();
}

class _TextMarkdownPreviewState extends State<TextMarkdownPreview> {
  // ---------- State ----------

  Offset? _dragPosition;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFont());
  }

  @override
  void didUpdateWidget(covariant TextMarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style.fontFamily != widget.style.fontFamily) unawaited(_loadFont());
  }

  Future<void> _loadFont() async {
    final family = widget.style.fontFamily;
    try {
      await loadTextFont(family);
      if (mounted && widget.style.fontFamily == family) setState(() {});
    } on Object {
      // Keep the saved choice and render the bundled fallback after failure.
    }
  }

  // ---------- Rendering ----------

  @override
  Widget build(BuildContext context) {
    final styleSheet = _styleSheet(context, widget.style);
    final content = widget.source.isEmpty
        ? _EmptyTextMarkdownPreview(
            key: const ValueKey('text-markdown-preview'),
            style: widget.style,
          )
        : MarkdownBody(
            key: const ValueKey('text-markdown-preview'),
            data: widget.source,
            blockSyntaxes: [LatexBlockSyntax()],
            inlineSyntaxes: [_TextImageSyntax(), LatexInlineSyntax()],
            builders: {
              'latex': LatexElementBuilder(
                textStyle: _fontStyle(context, widget.style).copyWith(fontSize: BSizes.markdownLatexFontSize),
              ),
            },
            styleSheet: styleSheet,
            syntaxHighlighter: _MarkdownCodeHighlighter(styleSheet.code!, BTheme.of(context).syntaxTheme),
            checkboxBuilder: (checked) => _buildCheckbox(checked, styleSheet),
            imageBuilder: (uri, title, alt) => _buildImage(uri, alt, widget.attachmentStore),
            onTapLink: (_, href, _) {
              widget.onInteract?.call();
              unawaited(_openLink(context, href));
            },
          );
    return GestureDetector(
      key: const ValueKey('text-markdown-preview-surface'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: widget.onEdit,
      onPanStart: (details) => _dragPosition = details.globalPosition,
      onPanUpdate: (details) {
        final position = details.globalPosition;
        widget.onMove(position - _dragPosition!);
        _dragPosition = position;
      },
      onPanEnd: (_) => _dragPosition = null,
      onPanCancel: () => _dragPosition = null,
      child: widget.scrollController == null
          ? Padding(padding: const EdgeInsets.all(24), child: content)
          : SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(24),
              child: content,
            ),
    );
  }
}

// ---------- Code highlighting ----------

class _MarkdownCodeHighlighter extends SyntaxHighlighter {
  _MarkdownCodeHighlighter(this.style, this.theme);

  static final _highlight = Highlight()
    ..registerLanguages({
      for (final language in CodeLanguage.values) language.name: ?language.mode,
    });

  final TextStyle style;
  final Map<String, TextStyle> theme;

  @override
  TextSpan format(String source, {String? language}) {
    final name = language?.trim().toLowerCase();
    final mode = name == null ? null : _highlight.getLanguage(name);
    final plain = TextSpan(text: source, style: style);
    if (mode == null) return plain;

    final limits = CodeHighlightThemeMode(mode: mode);
    if (source.length > limits.maxSize ||
        LineSplitter.split(source).any((line) => line.length > limits.maxLineLength)) {
      return plain;
    }

    final renderer = _MarkdownCodeRenderer(theme);
    _highlight.highlight(code: source, language: name!).render(renderer);
    return TextSpan(style: style, children: renderer.spans);
  }
}

// re_highlight's TextSpanRenderer copies growing lists and misses dotted token scopes.
// Remove this renderer when those fixes are available upstream or in a maintained fork.
class _MarkdownCodeRenderer implements HighlightRenderer {
  _MarkdownCodeRenderer(this.theme);

  final Map<String, TextStyle> theme;
  final spans = <TextSpan>[];
  final _scopes = <String?>[];

  @override
  void addText(String text) {
    var scope = _scopes.last;
    TextStyle? style;
    while (scope != null) {
      style = theme[scope];
      if (style != null) break;
      final separator = scope.indexOf('-');
      if (separator < 0) break;
      scope = scope.substring(separator + 1);
    }
    spans.add(TextSpan(text: text, style: style));
  }

  @override
  void openNode(DataNode node) {
    final parent = _scopes.isEmpty ? null : _scopes.last;
    final scope = parent == null || node.scope == null ? node.scope : '$parent-${node.scope}';
    _scopes.add(scope?.split('.').first);
  }

  @override
  void closeNode(DataNode node) => _scopes.removeLast();
}

// ---------- Empty state ----------

class _EmptyTextMarkdownPreview extends StatelessWidget {
  const _EmptyTextMarkdownPreview({required this.style, super.key});

  final TextNodeStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = BTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Click to edit',
        style: _fontStyle(context, style).copyWith(color: theme.colors.textMuted),
      ),
    );
  }
}

// ---------- Markdown styling ----------

MarkdownStyleSheet _styleSheet(BuildContext context, TextNodeStyle style) {
  final theme = BTheme.of(context);
  final colors = theme.colors;
  final base = _fontStyle(context, style).copyWith(height: 1.5);
  final semibold = textFontStyle(style.fontFamily, base.copyWith(fontWeight: FontWeight.w600));
  final heading = semibold.copyWith(color: style.color == null ? colors.textHeading : base.color);
  final italic = textFontStyle(style.fontFamily, base.copyWith(fontStyle: FontStyle.italic));
  final code = theme.typo.code.copyWith(
    color: colors.textPrimary,
    fontSize: BSizes.markdownBodyFontSize - 1,
    backgroundColor: colors.surfaceSubtle,
  );
  final table = base.copyWith(fontSize: BSizes.markdownBodyFontSize - 1, height: 1.45);

  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    a: base.copyWith(color: colors.accent),
    p: base,
    code: code,
    h1: heading.copyWith(fontSize: BSizes.markdownBodyFontSize + 10, fontWeight: FontWeight.w600, height: 1.2),
    h2: heading.copyWith(fontSize: BSizes.markdownBodyFontSize + 8, fontWeight: FontWeight.w600, height: 1.25),
    h3: heading.copyWith(fontSize: BSizes.markdownBodyFontSize + 6, fontWeight: FontWeight.w600, height: 1.3),
    h4: heading.copyWith(fontSize: BSizes.markdownBodyFontSize + 4, fontWeight: FontWeight.w600, height: 1.35),
    h5: heading.copyWith(fontSize: BSizes.markdownBodyFontSize + 2, fontWeight: FontWeight.w600, height: 1.35),
    h6: heading.copyWith(fontWeight: FontWeight.w600, height: 1.4),
    em: italic,
    strong: semibold,
    del: base.copyWith(decoration: TextDecoration.lineThrough),
    blockquote: base,
    img: base,
    checkbox: base.copyWith(color: colors.accent, fontSize: BSizes.defaultIconSize),
    listBullet: base,
    tableHead: heading.copyWith(fontSize: table.fontSize, height: table.height),
    tableBody: table,
    codeblockDecoration: BoxDecoration(color: colors.surfaceSubtle),
  );
}

Widget _buildCheckbox(bool checked, MarkdownStyleSheet styleSheet) => Padding(
  padding: styleSheet.listBulletPadding!,
  child: Text.rich(
    TextSpan(
      style: styleSheet.p,
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: styleSheet.checkbox!.fontSize,
            color: styleSheet.checkbox!.color,
          ),
        ),
      ],
    ),
    textAlign: TextAlign.center,
  ),
);

TextStyle _fontStyle(BuildContext context, TextNodeStyle style) {
  final base = TextStyle(
    fontSize: BSizes.markdownBodyFontSize,
    color: style.color ?? BTheme.of(context).colors.textPrimary,
  );
  return textFontStyle(style.fontFamily, base);
}

// ---------- Images ----------

const _imagePadding = EdgeInsets.symmetric(horizontal: 12);

Widget _buildImage(Uri uri, String? alt, AttachmentStore attachmentStore) {
  final path = uri.toString();
  if (attachmentPathPattern.hasMatch(path)) {
    return FutureBuilder<Uint8List>(
      future: attachmentStore.read(path),
      builder: (_, snapshot) => switch (snapshot) {
        AsyncSnapshot(hasData: true, data: final bytes?) => Padding(
          padding: _imagePadding,
          child: Image.memory(
            bytes,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (_, _, _) => _TextImageError(alt: alt),
          ),
        ),
        AsyncSnapshot(hasError: true) => _TextImageError(alt: alt),
        _ => const SizedBox.shrink(),
      },
    );
  }
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.host.contains('%')) {
    return _TextImageError(alt: alt);
  }
  return Padding(
    padding: _imagePadding,
    child: Image.network(
      uri.toString(),
      width: double.infinity,
      fit: BoxFit.fitWidth,
      errorBuilder: (_, _, _) => _TextImageError(alt: alt),
    ),
  );
}

// ---------- Markdown syntax ----------

class _TextImageSyntax extends md.InlineSyntax {
  _TextImageSyntax()
    : super(
        r"""!\[([^\]]*)\]\((?:<([^>]*)>|([^\s)]+))(?:\s+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?\)""",
        startCharacter: 33,
      );

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    startMatchPos ??= parser.pos;
    final match = pattern.matchAsPrefix(parser.source, startMatchPos);
    if (match == null) return false;
    final source = match[2] ?? match[3]!;
    if (Uri.tryParse(source) != null) return false;
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final image = md.Element.empty('img')
      ..attributes['src'] = 'http://invalid-image'
      ..attributes['alt'] = match[1]!;
    final title = match[4] ?? match[5] ?? match[6];
    if (title != null) image.attributes['title'] = title;
    parser.addNode(image);
    return true;
  }
}

class _TextImageError extends StatelessWidget {
  const _TextImageError({this.alt});
  final String? alt;

  @override
  Widget build(BuildContext context) => Semantics(
    label: alt,
    child: const Icon(Icons.broken_image_outlined),
  );
}

// ---------- Links ----------

Future<void> _openLink(BuildContext context, String? href) async {
  final uri = href == null ? null : Uri.tryParse(href);
  final supported = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  if (supported) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } on Exception {
      // The same feedback covers unavailable and failed platform launchers.
    }
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Could not open link')),
  );
}
