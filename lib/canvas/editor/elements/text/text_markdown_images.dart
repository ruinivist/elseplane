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
  TextMarkdownImages(String source, this.attachmentStore, {String canvasDirectory = ''})
    : canvasDirectory = canvasDirectory {
    validateAttachmentDirectory(canvasDirectory);
    synchronize(source);
  }

  final AttachmentStore attachmentStore;
  String canvasDirectory;
  Set<String> _sources = {};
  final _images = <String, _RetainedImage>{};
  final _localImages = <String>{};
  bool _retired = false;

  /// Returns a retained provider, null while loading, or a failed snapshot.
  ({ImageProvider<Object>? provider, bool failed}) resolve(Uri uri) {
    final source = uri.toString();
    if (_retired || !_sources.contains(source)) return (provider: null, failed: true);
    final identity = _identityForSource(source);
    if (isCanvasAttachmentReference(source)) _localImages.add(identity);
    final image = _images.putIfAbsent(identity, () {
      final image = _RetainedImage(notifyListeners);
      if (isCanvasAttachmentReference(source)) {
        unawaited(_loadAttachment(identity, image));
      } else {
        image.attach(NetworkImage(identity));
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
    final identities = _sources.map(_identityForSource).toSet();
    for (final identity in _images.keys.where((identity) => !identities.contains(identity)).toList()) {
      _images.remove(identity)!.retire();
      _localImages.remove(identity);
    }
  }

  void setCanvasDirectory(String directory) {
    validateAttachmentDirectory(directory);
    if (canvasDirectory == directory) return;
    canvasDirectory = directory;
    for (final identity in _localImages) {
      _images.remove(identity)?.retire(evict: true);
    }
    _localImages.clear();
    if (_sources.any(isCanvasAttachmentReference)) notifyListeners();
  }

  void invalidateAttachmentPaths(Set<String> paths) {
    var changed = false;
    for (final source in _sources.where(isCanvasAttachmentReference)) {
      final key = resolveAttachmentPath(canvasDirectory, source);
      if (!paths.contains(key)) continue;
      _images.remove(key)?.retire(evict: true);
      _localImages.remove(key);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  String _identityForSource(String source) =>
      isCanvasAttachmentReference(source) ? resolveAttachmentPath(canvasDirectory, source) : source;

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
    _localImages.clear();
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

  void retire({bool evict = false}) {
    retired = true;
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
    final current = provider;
    provider = null;
    if (evict && current != null) unawaited(current.evict().then<void>((_) {}));
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
