# Canvas pan performance at low zoom

Reviewed: 2026-11-22

## Scope

Panning the `web links` canvas becomes choppy at 10% zoom. The canvas contains 94 elements: 31 PNG images, 25 generic link cards, 37 text blocks, and one pen stroke. Most or all of the elements fit in a centered overview. The target is 144 frames per second, or 6.94 ms per frame.

## Measured findings

### 1. Wide spatial queries: confirmed and fixed upstream

Lowering the minimum zoom from 50% to 10% kept the grid's 3.4× build extent on each axis. With a 1440×900 viewport and 100×100 world-space cells, the old lookup probes about 150,000 cells at 10%, versus 6,200 at 50%, even if most are empty. The grid fix (`adfb5eb`) scans stored object bounds when there are fewer objects than cells to visit.

Median time per query in the Chromium test runner:

| Synthetic workload | Before (`82c3b07`) | After (`adfb5eb`) |
| --- | ---: | ---: |
| 10% pan, 94 objects | 28.70 ms | 0.020 ms |
| 50% pan, 94 objects | 1.22 ms | 0.018 ms |
| Narrow nine-cell query, 10,000 objects | 3.24 µs | 3.35 µs |

The two versions returned the same IDs at all sampled positions, and all 107 grid tests passed. The narrow lookup was about 0.12 µs slower in Chromium. These timings cover the index only, not whole-app frames. The app must resolve the fixed grid revision to benefit.

### 2. Glass: strongest measured cost after the grid fix

A scratch Elseplane release build at `d107195` used the fixed grid and enabled the surface-style toggle. Headless Chromium used CanvasKit with SwiftShader software rendering. The actual canvas and its PNGs were imported locally and warmed up. Three runs per style used the same scripted pointer path at 10%, with movement verified visually.

| Surface style | Median animation callback interval | 95th percentile | Intervals over 20 ms |
| --- | ---: | ---: | ---: |
| Glass | 49.9 ms | 133–150 ms | About half |
| Solid | 16.7 ms | 16.7–16.8 ms | None |

Idle callbacks were also about 16.7 ms apart. The browser trace showed longer main-thread animation callbacks and more software graphics work in Glass, but did not isolate raster stages. Input delivery also varied under load. The test switched the entire surface style, not just backdrop blur. Callback spacing does not measure presented frames, and these results neither rank costs on a hardware GPU nor show that Solid meets the 144 FPS budget.

## Other candidates, not yet timed

- **Grid layout and paint on pan.** Each pan update rebuilds the positioned-child list, runs parent layout, and walks the mounted children to paint. This can touch nearly every object at overview zoom. It does not mean every card is rebuilt from scratch or every child reruns its own layout.
- **Image rendering.** [Image blocks](../../lib/canvas/editor/elements/media/media_element_view.dart) request offscreen layers for anti-aliased clips. The 31 PNGs contain 36.5 million source pixels, but together draw roughly 0.21 million square CSS pixels at 10%. Decode and memory costs may affect opening the canvas; the warm pan did not isolate clipping or texture costs.
- **Media overlays.** The same media view keeps a layout-aware overlay portal open even when its controls are hidden. Up to 56 mounted media items can contribute work during a pan. The cost has not been measured separately.

## Next measurement

Compare identical warm pans in a hardware-accelerated release build with only backdrop blur toggled. Record median and 95th-percentile frame times and missed refreshes. [Proposed ADR 0008](../adr/0008-simplify-glass-at-overview-zoom.md) describes the visual trade-off. If turning off blur leaves a material gap, isolate camera-driven layout and paint before testing image clips or media overlays.
