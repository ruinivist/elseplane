// Retains inline image loads and streams for one text element.
// Owned by TextEditorResources rather than lazily culled Markdown widgets.

import 'dart:async';

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_markdown_plus/latex.dart';
import 'package:markdown/markdown.dart' as md;

/// Lazily loads referenced images and keeps their streams alive across culling.
class TextMarkdownImages extends ChangeNotifier {
  TextMarkdownImages(String source, this.attachmentStore) {
    synchronize(source);
  }

  final AttachmentStore attachmentStore;
  Set<String> _sources = {};
  final _images = <String, _RetainedImage>{};
  bool _retired = false;

  /// Returns a retained provider, null while loading, or a failed snapshot.
  ({ImageProvider<Object>? provider, bool failed}) resolve(Uri uri) {
    final source = uri.toString();
    if (_retired || !_sources.contains(source)) return (provider: null, failed: true);
    final image = _images.putIfAbsent(source, () {
      final image = _RetainedImage(notifyListeners);
      if (attachmentPathPattern.hasMatch(source)) {
        unawaited(_loadAttachment(source, image));
      } else {
        image.attach(NetworkImage(source));
      }
      return image;
    });
    return (provider: image.provider, failed: image.failed);
  }

  void synchronize(String source) {
    if (_retired) return;
    final document = md.Document(
      inlineSyntaxes: [TextImageSyntax()],
      extensionSet: md.ExtensionSet(
        [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, const LatexBlockSyntax()],
        [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexInlineSyntax()],
      ),
      encodeHtml: false,
    );
    _sources = _imageSources(document.parse(source)).toSet();
    for (final source in _images.keys.where((source) => !_sources.contains(source)).toList()) {
      _images.remove(source)!.retire();
    }
  }

  Future<void> _loadAttachment(String source, _RetainedImage image) async {
    try {
      final bytes = await attachmentStore.read(source);
      if (image.retired) return;
      image.attach(MemoryImage(bytes));
    } on Object {
      if (image.retired) return;
      image.failed = true;
    }
    if (!image.retired) notifyListeners();
  }

  /// Invalidates pending work immediately, before consumers detach.
  void retire() {
    _retired = true;
    for (final image in _images.values) {
      image.retire();
    }
    _images.clear();
    _sources.clear();
  }

  @override
  void dispose() {
    retire();
    super.dispose();
  }
}

class _RetainedImage {
  _RetainedImage(this.onChanged);

  final VoidCallback onChanged;
  ImageProvider<Object>? provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool failed = false;
  bool retired = false;

  void attach(ImageProvider<Object> image) {
    provider = image;
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      // Retain the stream without retaining the listener's ImageInfo clone.
      // Mounted Image widgets handle their own frame and layout notifications.
      (info, _) => info.dispose(),
      onError: (error, stack) {
        if (retired) return;
        failed = true;
        // A cached stream can fail synchronously during preview construction.
        // Its snapshot already contains the failure; only async changes notify.
        if (_listener != null) onChanged();
      },
    );
    _stream = stream;
    stream.addListener(listener);
    _listener = listener;
  }

  void retire() {
    retired = true;
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
    provider = null;
  }
}

Iterable<String> _imageSources(List<md.Node> nodes) sync* {
  for (final node in nodes.whereType<md.Element>()) {
    if (node.tag == 'img') {
      final uri = Uri.tryParse(node.attributes['src'] ?? '');
      if (uri != null &&
          (attachmentPathPattern.hasMatch(uri.toString()) ||
              uri.scheme == 'https' && uri.host.isNotEmpty && !uri.host.contains('%'))) {
        yield uri.toString();
      }
    }
    if (node.children != null) yield* _imageSources(node.children!);
  }
}

// Keep discovery and preview parsing consistent for malformed image destinations.
class TextImageSyntax extends md.InlineSyntax {
  TextImageSyntax()
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
