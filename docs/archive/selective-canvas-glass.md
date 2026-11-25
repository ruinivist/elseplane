# Implement selective canvas glass

Status: complete; implemented and verified on web.

## Scope

Implement the [selective canvas glass target](../specs/selective-canvas-glass.md)
and [ADR 0010](../adr/0010-skip-blur-on-clear-canvas-backdrops.md) on web.
Reuse the existing runner on `benchmark/glass`. Keep the runner and benchmark
hooks on that branch, not in production.
Do not change saved styles, settings, blur strength, app chrome, media
surfaces, or the grid dependency.

## Design

`CanvasView` owns the decisions because it already projects editor geometry
and effective paint order into the grid. At the end of a geometry or order
update, project a back-to-front snapshot of canvas-space footprints, with
the active foreground element last. Use the existing element geometry and
retained resources for measured sizes. Account for rotated bounds, code
titles, and painted outsets such as strokes and halos. Use a single
conservative footprint and decision for a code block and its title. Treat
unknown or unreliable footprints as possible contributors to every later
backdrop. Do not depend only on currently mounted widgets.

In the first implementation, treat auto-height text as unmeasured. Its
declared minimum height does not bound what Markdown can paint, especially
when images load. Keep blur on auto-height Glass text and on Glass blocks
painted after an unmeasured note. This can reduce the speedup on boards with
auto-height notes. Defer live layout tracking unless the representative-board
results show that this fallback leaves too few cards eligible.

For the first implementation, expand the card's sampling rectangle by
32 canvas pixels per side, then test it against earlier objects' paint
bounds. Include boundary contact. Keep blocker paint outsets separate
from the sampling margin. This margin is a measured starting point, not an
engine guarantee; adjust it only if the validation shows a visible miss.
Use a simple back-to-front scan first. Do not use the existing grid
interaction-overlap query as a backdrop oracle: it skips unmeasured objects
and does not include filter reach or paint outsets.

Cache the eligible IDs in canvas presentation and pass the result to text
and code views. Those views pass a boolean, defaulting to blur enabled, to
their `GlassSurface` calls. Leave all other callers at the default. Recompute
after relevant document/order changes, activation changes the paint order,
or resource/measurement changes the footprint. Publish only changed results.
Camera changes alone do not invalidate eligibility. On initialization or
invalidation without a reliable result, use full blur. Do not persist any
eligibility state.

## Steps and verification

1. Add classifier and canvas wiring. Test order and active lift, rotated
   bounds, margin contact, paint outsets, and missing or late bounds,
   including the auto-height fallback.
2. Wire text body and code body/title. Add focused Chrome tests showing
   that isolated cards can skip blur, and that blur is restored during
   movement onto a photo or lower card, reordering, and layout updates.
   Check that panning and zooming by themselves do not recalculate eligibility,
   and that normal toolbar and media rendering still use their defaults.
3. Use the existing runner to compare full blur with the production policy
   in accelerated Chromium release runs. Match warm camera paths, viewport,
   device-pixel ratio, and refresh rate. Test overview and normal zoom on
   the dense fixture and on a board based on the bundled Demo with photos,
   overlapping cards, clear grid, and an auto-height note. Record median,
   p95, budget misses, eligible counts, and edit recomputation cost. Repeat
   the blur-strength, all-off, or margin comparisons only if the new
   results point to a problem they can help explain.
4. Inspect stills and real pointer drags at overview and normal zoom.
   Check high-contrast edges just outside a card, the grid on isolated
   cards, selection contrast, and movement over photos and lower cards.
   Require a repeatable gain on the dense board, no meaningful regression
   on the representative board, and no objectionable loss of softening.
   If those checks fail, keep the current blur in production and record
   why before adjusting the policy.
5. Run focused Chrome tests, `flutter analyze`, and `flutter build web`.
   Run the full Chrome suite before committing the implementation.

## Results

The focused tests, full Chrome suite (819 passed, four skipped),
`flutter analyze`, and `flutter build web` passed. The
[validation results](../research/canvas-pan-performance.md#implementation-validation)
record the repeatable dense-board gain, the Demo-based comparison, and
the visual checks. The implementation keeps the 32 canvas-pixel margin
and the conservative fallback for auto-height text.
