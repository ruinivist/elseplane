# UI architecture

## Ownership

- App-wide Flutter primitives live in `lib/ui/common/`; canvas-specific widgets
  live in `lib/canvas/editor/widgets/`. Feature widgets stay with their owning
  feature.
- `ui/common` depends on Flutter and theme, never on a feature. The theme owns
  semantic values, concrete Starless Light palette and typography, syntax
  styles, and reusable app-wide geometry. Components own their layout details;
  equal numeric values alone do not establish shared meaning.
- Components read semantic `BTheme` values internally. Do not expose visual
  overrides without a concrete product requirement. Expose behavior parameters
  required by current consumers, not speculative flexibility.
- Ordinary icon and text actions inherit app-theme button states. Use
  `SurfaceIconButton` when an action needs its own raised surface; keep feature
  layout and selection local. Retain shared primitives only with production
  consumers.

## Dependencies and reuse

- Use `scroll_animator` 0.3.0 with `ChromiumEaseInOut` for smooth pointer
  scrolling.
- Keep spatial rendering, culling, navigation mechanics, and generic overlap
  calculations in the owned `infinite_lazy_grid` library. Expose non-mutating
  arrangement calculation there; commit its result through editor operations.
- Use the `flutter_markdown_plus` fork's exposed styling API first. Modify the
  fork when its rendering mechanics cannot achieve required styling.
- `lib/canvas/editor/elements/media/media_element_view.dart` owns one private
  `_MediaBody` for shared tap, drag, cancellation, device filtering, sizing, and
  resize animation. Image content keeps its image clip and selection border;
  `MediaLinkCard` remains the link content, with only the keyboard and semantics
  wrapper around the shared body. Link cards show resolved host and path without
  scheme, query, or fragment; raw text is only the fallback when resolution
  fails. Media resources stay with their existing resource owner. Do not add
  provider-specific widgets or a generic media framework.
- Isolate platform implementations and reuse installed dependencies.

## Previews and tests

Reusable UI widgets have annotated previews. Shared primitive and preview tests
belong under `test/ui/`; canvas-specific controls and tests belong to the canvas
editor widgets owner. Verify behavior and failure boundaries, not theme-token
values. Mirror behavior tests with their owner, check import boundaries, and
verify web only at this stage. Keep the interaction model current;
implementation shortcuts do not silently redefine it.
