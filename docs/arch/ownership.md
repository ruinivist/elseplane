# Ownership and dependencies

## Project structure

```text
lib/
  main.dart                         # Initialise Flutter and start the app
  app/
    app.dart                         # Compose dependencies, theme, and root UI
    workspace.dart                   # Connect editor, library, settings lifetimes
    feature_flags.dart
  canvas/
    document/
      canvas_document.dart           # Immutable ordered document
      canvas_element.dart             # Sealed element values and saved enums
      media_url.dart                  # Pure external media URL policy
      document_codec.dart             # Encoding, decoding, boundary validation
    geometry/                        # Paths, bounds, hit tests, transforms
    editor/
      editor_session.dart            # Document writes and interaction state
      editor_history.dart            # Typed snapshots and operation grouping
      canvas_input.dart              # Pointer ownership and gesture transitions
      canvas_shortcuts.dart          # Focus-aware keyboard actions
      canvas_clipboard.dart          # Clipboard interpretation and edit workflow
      canvas_page.dart               # Compose canvas and controls
      canvas_view.dart               # Project document into infinite_lazy_grid
      element_resources.dart         # Resources retained by element identity
      tools/                         # Creation gestures and placement
      elements/                      # text/, code/, media/, shape/, pen/, arrow/
      widgets/                       # Shared canvas chrome and controls
      previews/                      # Canvas component previews
  library/
    canvas_library.dart               # File/folder values and hierarchy rules
    library_controller.dart           # Library operations and save queue
    library_store.dart                # Storage contract and implementation
    transfer/                         # Project/backup codecs and import staging
    widgets/                          # File picker and file tree
    previews/
  attachments/
    attachment_store.dart             # Byte-storage contract
    image_import.dart                 # Validate images and create attachments
    attachment_store_web.dart         # Browser implementation
  settings/                          # Application preferences and settings UI
  theme/                             # Semantic theme, concrete styles, font resources
  ui/
    common/                          # App-wide Flutter primitives
    previews/                        # Previews of those primitives
test/                                # Mirrors the owner of each behavior
```

Create a file or folder when it has a responsibility; this tree does not require
empty scaffolding.

## Allowed dependencies

| Owner | May depend on | Boundary |
| --- | --- | --- |
| `app` | All feature entry points | Constructs dependencies and connects lifetimes. |
| `document` | Value types and serialization support | No widgets, theme lookup, loading, storage, or browser APIs. |
| `geometry` | Document values and graphics/math primitives | Computes geometry without application state or I/O. |
| Editor logic | Document, geometry, narrow I/O contracts, Flutter input/notifier primitives | No widget construction or concrete storage implementations. |
| Editor presentation | Editor logic, Flutter, theme, shared UI, grid | Requests edits; never writes document fields. |
| `library` | Document and attachments | Never imports the editor; library widgets additionally use Flutter, theme, and shared UI. |
| `attachments` | Byte/image primitives and platform storage | Browser imports stay in the browser implementation. |
| `ui/common` | Flutter and theme | Never imports a feature. |
| `theme` | Flutter, font and highlighting dependencies | Never imports features or app composition. |

## Document ownership

The document library keeps sealed element values and private codec helpers in
Dart parts alongside generated serialization. Geometry uses ordinary imports.
Published document collections are unmodifiable copies; unchanged immutable
elements and stroke samples may be shared between snapshots. `Offset`, `Size`,
`Rect`, and `Color` are suitable value types. Saved enums belong to the
document; background builders and syntax-highlighting mappings belong to
presentation. Font-download availability does not determine document validity.
The pure media URL policy belongs to `document/media_url.dart`; it has no widget,
network, or storage dependencies. Editor input, clipboard handling, project
import, and library restore share it at their trust boundaries. The library uses
the document policy without importing the editor.

Keep one in-memory representation per concept. Convert JSON and color formats
at boundaries, validate external input, and enforce invariants on edits.

## App and library ownership

`main.dart` initializes Flutter and starts the app. `app/app.dart` constructs
dependencies and owns root appearance state and preference persistence.
Compile-time flags live in `app/feature_flags.dart`; app composition gates
appearance callbacks, and Settings derives control availability from those
callbacks without importing app composition.

Workspace owns the open editor session and connects its snapshots to the
library. Settings preferences are independent of document history; resolve
defaults when creating elements, and do not rewrite existing content when
appearance settings change. Library durability details are in
[persistence](persistence.md).

## Design and file rules

- Keep one owner for each state, policy, and lifecycle. Share rules whose
  consumers must change together; an abstraction must remove existing
  duplication, enforce an invariant, or isolate an external boundary.
- Extend actual variation points. Explicit exhaustive dispatch is appropriate
  for the closed set of element types; a shared contract promises only behavior
  every implementation supports, and consumers receive only needed operations.
- Keep related small declarations together; remove obsolete paths, unused
  options, and speculative flexibility. Equal numeric values do not establish
  that two values have the same meaning.
- Use descriptive `snake_case` Dart filenames and one element vocabulary:
  `TextElement` is saved data, `TextElementView` renders it,
  `TextEditorResources` retains Flutter resources, `PenTool` creates strokes,
  `EditorSession` owns an editing lifetime, `LibraryStore` persists, and
  `DocumentCodec` converts representations. Avoid vague `manager`, `helpers`,
  and `utils` buckets.
- Use ordinary imports for independent components. Reserve `part` for generated
  code or a genuinely inseparable Dart library. Sealed variants may share one
  file. Keep feature widgets with their feature.
