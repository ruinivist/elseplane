# Selective canvas glass

Status: accepted; implemented on web.

## Scope

This applies to canvas text and code blocks with their background set to Glass,
including the code body and any visible code title. In app-wide Glass mode,
it also applies to generic and rich link cards and the Image tool's inline URL
card shown when the block does not display an image or link card. The rule
applies while the block is inactive, active, selected, or being edited.

## Behavior

- Both rendering paths retain the rounded clip, border, exterior halo, and
  selection outline. The current Glass tint, including its selected variant,
  is the source color for both paths.
- Keep the existing full-strength blur if earlier-painted content could
  contribute to the backdrop, even when the objects do not visibly touch.
  Earlier content can include images, media cards, text, code, shapes,
  strokes, and paint outside their layout bounds, including the current
  theme's glass halo. Content painted above the block does not contribute.
  Account for the active block's temporary lift.
  With full blur, keep the translucent fill.
- When only the plain background or dot grid can contribute, the block may
  omit blur. When it does, blend the current Glass tint over the theme's plain
  canvas background color and use the resulting opaque fill. The dot grid
  does not show through this fill. When bounds, paint order, or eligibility
  are uncertain, use the full-blur treatment. It is acceptable to retain
  blur on some clear backdrops.
- Apply the same rule at every zoom. Do not change treatment solely because
  zoom crosses a threshold. As a card or its backdrop moves, resizes, or
  changes stacking, restore translucency and full blur together as soon as
  they are needed; do not wait until the gesture ends.
- For the inline URL card, a conservative rectangle can stand in for exact
  layout bounds. It must cover the full card at the current text scale,
  including three lines of input or a taller wrapped placeholder. Use it
  both when checking the card's own backdrop and when checking whether its
  paint can reach another card's backdrop. Account for rotation and the
  exterior halo.
- Do not change hit testing, editing, selection, stacking, or the saved
  background choice. Solid media surfaces, image pixels, and thumbnails
  are unchanged. The floating URL editor below an existing image or link
  card, toolbar, zoom controls, tool options, menus, dialogs, file picker,
  and notifications keep their existing rendering.

## Acceptance criteria

- An isolated Glass block can skip blur without showing sharp grid dots
  through its fill. In both themes, moving a few pixels across the cutoff
  does not cause a conspicuous change in apparent opacity against the grid.
  Check normal and selected cards against the full-blur look.
- A detailed photo, a lower block's text or edge, or another painted mark
  behind the glass is still softened. Moving a block across those backdrops,
  or changing stack order, does not leave a stale unblurred state.
- Generic and rich link cards and the inline URL card can skip blur over
  clear canvas. An inline URL card wrapped to three lines still blurs content
  behind its lower edge and counts as earlier paint for cards above it.
  The floating URL editor keeps live blur in Glass mode.
- Unknown bounds retain blur. Transparent and Card backgrounds and other
  glass surfaces remain unchanged.
