# Selective canvas glass

Status: accepted; implemented on web.

## Scope

This applies to canvas text and code blocks with their background set to
Glass, including the code body and any visible code title. It applies when
the block is inactive, active, selected, or being edited. Other surfaces
continue to follow the [interaction model](interaction-model.md#appearance).

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
- Do not change hit testing, editing, selection, stacking, or the saved
  background choice. Toolbar, zoom controls, tool options, menus, dialogs,
  file picker, notifications, and media link cards and URL panels keep
  their current rendering.

## Acceptance criteria

- An isolated Glass block can skip blur without showing sharp grid dots
  through its fill. In both themes, moving a few pixels across the cutoff
  does not cause a conspicuous change in apparent opacity against the grid.
  Check normal and selected cards against the full-blur look.
- A detailed photo, a lower block's text or edge, or another painted mark
  behind the glass is still softened. Moving a block across those backdrops,
  or changing stack order, does not leave a stale unblurred state.
- Unknown bounds retain blur. Transparent and Card backgrounds and other
  glass surfaces remain unchanged.
