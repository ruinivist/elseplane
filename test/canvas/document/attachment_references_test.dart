import 'dart:ui';

import 'package:elseplane/canvas/document/attachment_references.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:flutter_test/flutter_test.dart';

const _path0 = 'attachments/123e4567-e89b-42d3-a456-426614174000.png';
const _path1 = 'attachments/123e4567-e89b-42d3-a456-426614174001.webp';

void main() {
  test('discovers references from any element iterable with existing Markdown semantics', () {
    final elements = [
      TextElementData(
        id: 'text',
        position: Offset.zero,
        width: 420,
        height: null,
        markdown:
            '''
![inline]($_path0)

```markdown
![ignored]($_path1)
```
''',
        style: const TextNodeStyle(fontFamily: 'Inter', color: Color(0xff201c1a)),
      ),
      MediaElementData(id: 'media', position: Offset.zero, width: 240, url: '  $_path1  '),
    ];

    expect(canvasAttachmentPaths(elements), {_path0, _path1});
    expect(canvasAttachmentPaths(elements.take(1)), {_path0});
  });
}
