import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:elseplane/library/debug/demo_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

import '../demo_asset_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installDemoAssetFixture);

  test('decodes the bundled demo as one root canvas with its referenced image', () async {
    expect(demoAssetReadCount, 0);
    final demo = await loadDemoCanvas();

    expect(demoAssetReadCount, 1);
    expect(demo.canvases.keys, {'Demo.canvas.json'});
    expect(demo.skippedCanvases, isEmpty);
    expect(demo.directories, isEmpty);
    expect(demo.attachments.keys, {demoImagePath});
    expect(demo.attachments[demoImagePath], demoImageBytes);
    expect(
      demo.canvases['Demo.canvas.json']!.elements.whereType<MediaElementData>().single.url,
      demoImagePath,
    );
  });
}
