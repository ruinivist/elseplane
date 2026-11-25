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

## Selective blur and zoom

On 2026-11-24, a release CanvasKit benchmark on Elseplane `e3d76d1` compared
Glass text and code cards on a mixed board: 48 isolated cards over the grid
and 48 cards with overlaps, stripes, and a large photo. Chromium reported
hardware acceleration. The viewport was 1440 × 900 CSS pixels at DPR 1,
and the display ran at 164.96 Hz (6.06 ms budget).

At 10%, lowering blur sigma from 16 to 12, 8, or 4 did not improve median
or p95 callback intervals when all cards kept blur. A detector with a
blanket 128 canvas-pixel margin skipped just six cards and did not
improve the median. A 32 canvas-pixel sampling margin plus separate
paint outsets skipped 48 cards. It matched the hand-labeled result,
24.3 / 30.4 ms to 12.2 / 18.3 ms median / p95, and the photo and overlap
crop was pixel-identical with full blur. Turning all blur off, a
performance control only, reached 12.1 / 12.2 ms. The detector did not
recalculate during panning. An earlier version of the detector took
0.10 ms median and 0.30 ms p95 to recalculate on 22 scripted moves on
this board; that was not a full drag measurement.

The follow-up used the same camera path for full and selective blur at
each zoom, with two runs per condition:

| Zoom | Full blur median / p95 | Selective blur median / p95 |
| ---: | ---: | ---: |
| 10% | 24.3 / 30.3 ms | 12.2 / 18.3 ms |
| 20% | 42.6 / 48.7 ms | 18.2 / 42.5 ms |
| 30% | 36.4 / 42.5 ms | 24.2 / 24.4 ms |
| 50% | 30.4 / 36.5 ms | 24.2 / 30.4 ms |
| 100% | 6.2 / 12.2 ms | 6.1 / 12.2 ms |

These are browser animation callback intervals, not presented-frame or
GPU timings. Visible card counts and area vary with zoom, so compare
within rows. At 25% and 30%, the visible difference in matched stills
was mainly a sharper grid under isolated cards. A separate edge test at
10% found photo-dependent differences confined to the immediate card
edge at a 32 canvas-pixel gap and none beyond the photo edge at 40 px
and larger gaps on that setup. This is not a renderer guarantee.

The bundled demo run for the experimental detector never acquired browser
focus, so it produced no timings.

## Implementation validation

The follow-up used the existing runner to compare the implementation's
backdrop decisions with full blur. It ran on hardware-accelerated Chromium
154 at 1440 × 900 CSS pixels, DPR 1, and 164.91 Hz (6.064 ms budget). The
Demo-based board included the bundled photo, an overlapping code card,
clear grid, and an auto-height note. Each condition used two warm runs of
240 callbacks in forward and reverse condition order.

| Board | Zoom | Full blur median / p95 (ms) | Selective median / p95 (ms) | Over budget, full → selective | Over budget + 1 ms, full → selective |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dense | 10% | 24.30 / 30.40 | 18.20 / 18.30 | 480 → 480 | 479 → 479 |
| Dense | 100% | 12.10 / 18.20 | 6.15 / 12.20 | 422 → 397 | 266 → 223 |
| Demo-based | 10% | 6.10 / 6.20 | 6.10 / 6.20 | 320 → 327 | 0 → 0 |
| Demo-based | 100% | 6.10 / 6.20 | 6.10 / 6.20 | 326 → 317 | 24 → 0 |

The dense board skipped blur on 48 of 96 cards. Both passes improved
median and p95 callback intervals at both zooms, but overview panning
still exceeded this display's refresh budget. The Demo-based board skipped
blur on one of six Glass cards at rest and showed no meaningful regression.
Its idle cadence was 6.10 ms, which explains why the strict 6.064 ms count
is less useful near idle. Neither board recalculated blur eligibility
during the measured pans. Across 50 scripted moves per board, the eligibility
update took 0.200 / 0.399 ms median / p95 on the dense board and
0.099 / 0.101 ms on the Demo-based board. These are detector timings,
not end-to-end edit timings.

Matched stills had pixel-identical photo and overlap crops on the dense
board at 10%, a layered-card crop on the dense board at 100%, and the
Demo-based photo and code overlap at both zooms. Real pointer drags
restored blur over the photo before release at both zooms and over a
lower text card at 100%. Selection remained visible at both zooms. At a
35 canvas-pixel gap above the photo, the matched stills showed slightly
sharper grid dots and no objectionable loss of softening. The timing
runs cover one device, display, and renderer, not frame presentation or
all real boards.
See [ADR 0010](../adr/0010-skip-blur-on-clear-canvas-backdrops.md) and the
[completed plan](../archive/selective-canvas-glass.md). The benchmark
harness and raw captures are not part of `main`.

### Opacity change on small moves

Later screenshots showed a more noticeable difference than the benchmark
stills: sharp grid dots were visible with blur off and nearly disappeared
after a small move. The tint did not change, but the card looked more
opaque when blur returned. The [updated specification](../specs/selective-canvas-glass.md)
keeps the full-blur look as the reference and uses a matched opaque fill
when blur is skipped. The timings above measured the initial translucent
path, not the opaque fill. Manual visual testing confirmed the new look.
The automated checks covered both themes and the selected fill; the
matched browser screenshot runs did not complete.
