// Embeds the portable demo project for debug builds.
// Used by the canvas picker to populate a new canvas.

import 'dart:convert';

import 'package:elseplane/canvas/persistence/canvas_project.dart';
import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';

part 'demo_canvas.g.dart';

// ---------- Demo project ----------

@JsonLiteral('demo.beyond.json', asConst: true)
Map<String, dynamic> get _demoJson => _$_demoJsonJsonLiteral;

Future<CanvasProject> loadDemoCanvas() {
  if (!kDebugMode) throw UnsupportedError('Demo is only available in debug builds');
  return decodeCanvasProject(Uint8List.fromList(utf8.encode(jsonEncode(_demoJson))));
}
