# Skip blur on clear canvas backdrops

Status: accepted; implemented on web.

Date: 2026-11-24

## Context

Live backdrop blur is the largest isolated pan cost at overview zoom on the
tested dense canvas. Turning off every filter made panning faster, but it
left sharp photo and lower-card details visible through the glass.
The [canvas pan research](../research/canvas-pan-performance.md#selective-blur-and-zoom)
compares reduced blur strength, selective skipping, and several backdrop
margins. Skipping 48 of 96 filters halved median callback spacing at 10%
with no pixel change in the photo and overlap crop. Reducing blur strength
did not improve median or p95 on that fixture. Selective skipping also helped
at 20%, 30%, and 50%; the median at 100% was essentially unchanged.

## Decision

Keep full-strength live blur on Glass text and code blocks whenever earlier
painted content could contribute to the backdrop. Skip the filter only when
the backdrop is clear except for the canvas background. The same rule applies
at every zoom. When skipping blur, use an opaque fill made by blending the
existing Glass tint over the theme's plain canvas color, using the selected
tint when applicable. Restore the translucent fill and full blur together
when the backdrop needs them. Leave all other glass surfaces unchanged.

Canvas presentation owns the backdrop decision. It uses conservative paint
bounds and effective stacking order and retains blur when information is
missing. Canvas presentation derives the halo's paint outset when the theme
changes and reuses it when projecting element bounds. The shared glass
primitive takes the decision as a rendering input; it does not query the
canvas. Eligibility is not saved and is not recalculated
just because the camera pans. No new preference, zoom cutoff, or layer cache
is part of the initial implementation.

## Alternatives

- [Drop blur at overview zoom](0008-simplify-glass-at-overview-zoom.md):
  declined because zoom alone does not tell us whether a photo or another card
  needs softening.
- Weaken each filter or share a lower-resolution backdrop: weaker blur did
  not help the measured configuration. Sharing a backdrop adds capture and
  invalidation work and complicates card-on-card stacking. Revisit only if
  selective skipping cannot recover enough performance.
- Use a zoom cutoff: defer until there is evidence of a visual or performance
  problem at a particular zoom. The initial policy avoids a zoom-driven flip.
- Keep the fill translucent without blur: the initial implementation did
  this. Sharp grid dots could appear or disappear after a small move across
  the eligibility boundary, making the card look as if its opacity changed.
  An opaque fill hides the dots without adding a separate grid effect.

## Consequences

The opaque fill hides grid dots; full blur can still leave faint dots
visible. Conservative bounds can leave filters enabled where a more exact
test would skip them. The benchmark
shows a gain on the dense fixture, not a guarantee for other boards or
displays. The [validation results](../research/canvas-pan-performance.md#implementation-validation)
record the Demo-based and interaction checks. The
[specification](../specs/selective-canvas-glass.md) defines the accepted target.
