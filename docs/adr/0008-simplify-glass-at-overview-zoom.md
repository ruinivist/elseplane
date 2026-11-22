# Simplify glass at overview zoom

Status: proposed

Date: 2026-11-22

## Context

Live glass blurs the scene behind each surface. That detail is useful at normal zoom, but it is harder to see when many small cards fit on screen. At 144 frames per second, each frame has about 6.94 ms.

The [canvas pan performance investigation](../research/canvas-pan-performance.md) measured a roughly threefold increase in median animation callback interval for Glass versus Solid at 10% zoom after the spatial lookup fix. The test used software rendering and changed the entire surface style. It justifies testing blur on its own, but does not establish its cost on a hardware GPU.

## Proposed decision

At overview zoom, draw canvas content that uses Glass with its translucent tint, outline, exterior shadow, and selection cues, but without live backdrop blur. Keep live blur on canvas content at normal zoom and on screen-space chrome such as toolbars, menus, and dialogs. Choose the zoom cutoff by checking when the visual difference becomes hard to see; avoid flicker around the cutoff. Do not change saved block styles, hit testing, or editing behavior.

The canvas presentation owns the zoom-dependent choice; shared surface widgets render the chosen treatment without depending on the canvas controller. The [interaction model](../specs/interaction-model.md) remains authoritative until this proposal is accepted, including its blur requirements for text and code blocks.

## Alternatives

- **Share a backdrop filter.** Flutter's `BackdropGroup` can combine filtering for non-overlapping surfaces. Test this if live blur at overview matters. Overlapping surfaces should not share a backdrop key if that changes what they blur.
- **Blur at lower resolution.** Filtering a smaller backdrop can preserve the soft look at lower cost, but adds rendering complexity. Revisit only if live blur still matters and sharing the filter is not enough.
- **Skip blur only while moving.** Restore live blur when panning settles. This preserves the stationary look but can make the blur switch noticeable every time the camera starts or stops.

## Validation before acceptance

Compare identical warm pans in a hardware-accelerated Chromium release build with live blur on and off, holding tint, outline, and shadow constant. Record median and 95th-percentile frame times and missed refreshes. Check overlapping cards, selection contrast, and the zoom transition. Keep the change only if the frame-time gain is meaningful and the overview still reads as Glass. If frame times remain above budget, profile the camera's layout and paint work separately.
