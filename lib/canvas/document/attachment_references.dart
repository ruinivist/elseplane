// Discovers local attachment references without document or storage mutation.
// Used by clipboard selections and document transfer flows.

import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:flutter_markdown_plus/latex.dart';
import 'package:markdown/markdown.dart' as md;

Set<String> canvasAttachmentPaths(Iterable<CanvasElementData> elements) {
  final paths = <String>{};
  for (final element in elements) {
    if (element case TextElementData(:final markdown)) {
      for (final image in _markdownImages(markdown)) {
        final path = image.attributes['src']!;
        if (isCanvasAttachmentReference(path)) paths.add(path);
      }
    } else if (element case MediaElementData(:final url)) {
      final path = url.trim();
      if (isCanvasAttachmentReference(path)) paths.add(path);
    }
  }
  return Set.unmodifiable(paths);
}

Iterable<md.Element> _markdownImages(String source) => _imageNodes(
  md.Document(
    extensionSet: md.ExtensionSet(
      [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, const LatexBlockSyntax()],
      [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexInlineSyntax()],
    ),
    encodeHtml: false,
  ).parse(source),
);

Iterable<md.Element> _imageNodes(List<md.Node> nodes) sync* {
  for (final node in nodes.whereType<md.Element>()) {
    if (node.tag == 'img') yield node;
    if (node.children != null) yield* _imageNodes(node.children!);
  }
}
