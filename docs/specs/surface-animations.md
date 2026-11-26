# Surface animations

Status: accepted; implemented on web, pending visual verification.

## Scope

This specification sets the animation rule for surfaces that support both
Glass and Solid. The current rollout covers Settings, the canvas file picker
(Explorer), the Delete confirmation in Explorer, the local Overwrite canvases
and Import result dialogs, the GitHub import and commit dialogs, and the
floating URL editor below an image or link card. It does not require changing
other surfaces or the inline URL card.

## Behavior

- A surface uses the same opening and closing motion in Glass and Solid. The
  surface style changes how it is painted, not how it moves.
- Animate the panel's geometry rather than fading the whole surface. Wherever
  a Glass panel is visible, its backdrop is blurred at full strength within its
  current bounds, from the first visible frame through the last. Keep the
  normal glass tint; do not fade it or the blur in separately.
- The dialogs in scope use a shared subtle scale-in and scale-out. Each keeps
  its existing backdrop color: dimming animates independently of the panel,
  and Explorer's backdrop stays clear.
- The floating media URL editor keeps its anchored scale motion on open and
  close, without a whole-panel fade in either style.
- Keep existing focus, dismissal, keyboard navigation, and save behavior.
  Clicking outside the GitHub import dialog still does not dismiss it.

## Acceptance criteria

- Open and close each surface in Glass mode over sharp text or a detailed
  image. The panel visibly scales, and content inside its visible bounds
  stays frosted throughout. Sharp content outside those bounds is expected.
- Repeat in Solid mode. Each surface follows the same motion and timing as in
  Glass mode. Dimmed backdrops animate independently in both styles, and
  Explorer never dims the background.
