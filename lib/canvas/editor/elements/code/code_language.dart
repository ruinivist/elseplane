// Maps saved code languages to labels and editor highlighting modes.
// Used by code blocks, Markdown rendering, and language selection controls.

import 'package:elseplane/canvas/document/canvas_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

// ---------- Languages ----------

/// Maps selectable language labels to editor highlighting modes.
/// Used by code block controls and rendering.
extension CodeLanguagePresentation on CodeLanguage {
  String get label => switch (this) {
    CodeLanguage.python => 'Python',
    CodeLanguage.typescript => 'TypeScript',
    CodeLanguage.javascript => 'JavaScript',
    CodeLanguage.java => 'Java',
    CodeLanguage.csharp => 'C#',
    CodeLanguage.cpp => 'C++',
    CodeLanguage.c => 'C',
    CodeLanguage.go => 'Go',
    CodeLanguage.rust => 'Rust',
    CodeLanguage.sql => 'SQL',
    CodeLanguage.bash => 'Bash',
    CodeLanguage.kotlin => 'Kotlin',
    CodeLanguage.swift => 'Swift',
    CodeLanguage.php => 'PHP',
    CodeLanguage.ruby => 'Ruby',
    CodeLanguage.dart => 'Dart',
    CodeLanguage.html => 'HTML',
    CodeLanguage.css => 'CSS',
    CodeLanguage.json => 'JSON',
    CodeLanguage.yaml => 'YAML',
    CodeLanguage.markdown => 'Markdown',
    CodeLanguage.plainText => 'Plain text',
  };

  Mode? get mode => switch (this) {
    CodeLanguage.python => langPython,
    CodeLanguage.typescript => langTypescript,
    CodeLanguage.javascript => langJavascript,
    CodeLanguage.java => langJava,
    CodeLanguage.csharp => langCsharp,
    CodeLanguage.cpp => langCpp,
    CodeLanguage.c => langC,
    CodeLanguage.go => langGo,
    CodeLanguage.rust => langRust,
    CodeLanguage.sql => langSql,
    CodeLanguage.bash => langBash,
    CodeLanguage.kotlin => langKotlin,
    CodeLanguage.swift => langSwift,
    CodeLanguage.php => langPhp,
    CodeLanguage.ruby => langRuby,
    CodeLanguage.dart => langDart,
    CodeLanguage.html => langXml,
    CodeLanguage.css => langCss,
    CodeLanguage.json => langJson,
    CodeLanguage.yaml => langYaml,
    CodeLanguage.markdown => langMarkdown,
    CodeLanguage.plainText => null,
  };

  CodeHighlightTheme? theme(Map<String, TextStyle> styles) => mode == null
      ? null
      : CodeHighlightTheme(
          languages: {name: CodeHighlightThemeMode(mode: mode!)},
          theme: styles,
        );
}
