// Renders Markdown, LaTeX, images, and links for text blocks.
// Used by the text tool whenever a text element is not being edited.

import 'dart:async';
import 'dart:typed_data';

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/canvas/persistence/attachments/store.dart';
import 'package:elseplane/canvas/tools/text/text_tool_settings.dart';
import 'package:elseplane/theme/fonts.dart';
import 'package:elseplane/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:markdown/markdown.dart' as md;
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
    super.key,
  });

  final String source;
  final TextNodeStyle style;
  final ScrollController? scrollController;
  final VoidCallback onEdit;
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
              'latex': LatexElementBuilder(textStyle: _fontStyle(widget.style)),
            },
            styleSheet: styleSheet,
            checkboxBuilder: (checked) => _buildCheckbox(checked, styleSheet),
            imageBuilder: (uri, title, alt) => _buildImage(uri, alt, widget.attachmentStore),
            onTapLink: (_, href, _) => _openLink(context, href),
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
        style: _fontStyle(style).copyWith(color: theme.colors.textMuted),
      ),
    );
  }
}

// ---------- Markdown styling ----------

MarkdownStyleSheet _styleSheet(BuildContext context, TextNodeStyle style) {
  final theme = BTheme.of(context);
  final colors = theme.colors;
  final base = _fontStyle(style).copyWith(height: 1.5);
  final semibold = textFontStyle(style.fontFamily, base.copyWith(fontWeight: FontWeight.w600));
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
    h1: semibold.copyWith(fontSize: BSizes.markdownBodyFontSize + 10, fontWeight: FontWeight.w600, height: 1.2),
    h2: semibold.copyWith(fontSize: BSizes.markdownBodyFontSize + 8, fontWeight: FontWeight.w600, height: 1.25),
    h3: semibold.copyWith(fontSize: BSizes.markdownBodyFontSize + 6, fontWeight: FontWeight.w600, height: 1.3),
    h4: semibold.copyWith(fontSize: BSizes.markdownBodyFontSize + 4, fontWeight: FontWeight.w600, height: 1.35),
    h5: semibold.copyWith(fontSize: BSizes.markdownBodyFontSize + 2, fontWeight: FontWeight.w600, height: 1.35),
    h6: semibold.copyWith(fontWeight: FontWeight.w600, height: 1.4),
    em: italic,
    strong: semibold,
    del: base.copyWith(decoration: TextDecoration.lineThrough),
    blockquote: base,
    img: base,
    checkbox: base.copyWith(color: colors.accent, fontSize: BSizes.defaultIconSize),
    listBullet: base,
    tableHead: semibold.copyWith(fontSize: table.fontSize, height: table.height),
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

TextStyle _fontStyle(TextNodeStyle style) {
  final base = TextStyle(fontSize: BSizes.markdownBodyFontSize, color: colorFromHex(style.color));
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
