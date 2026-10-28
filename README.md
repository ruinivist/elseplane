# elseplane

https://elseplane.ruiny.de/

Infinite canvas with first-class support for code and Markdown.

## Why?

Code and markdown are not at all supported in excalidraw.
Tldraw default doesn't as well, you can extend it via their SDK but the license
is too restrictive.

## Features

- code and markdown support
- a little bit nice ui
- more intuitive controls ( hopefully )
- less bloat ( focus is on keeping the ui out of the way )
- flutter so would be 100% cross platform ( need to test still )
- self host with sharing ( planned )

## Feature flags

Edit the `static const` values in `lib/app/feature_flags.dart` and rebuild the app.
`themeSelection` and `surfaceStyleSelection` default to `false`: the app uses
Dark and Glass, and hides their settings. Enable either flag to restore its
selector. New users start in Dark and Glass even when selection is enabled.

App composition owns these flags and supplies appearance callbacks to Settings.
Settings shows only the controls it receives callbacks for. Future tool flags
must guard activation and keyboard shortcuts as well as toolbar buttons.

## Touch replay tests

Run `make test-touch` to check touch ownership and replay two-finger motion in
Chromium. Set `CHROME_EXECUTABLE` if Chromium is installed somewhere other than
`/usr/bin/chromium`. After changing checkouts, run `flutter pub get --enforce-lockfile`
to refresh the generated dependency configuration.

The replay covers one stationary finger, two-finger panning, pinching, combined
pan/zoom, and rotation with 60 Hz input and independent 60 Hz or 120 Hz display
clocks. Paired updates arrive together; staggered updates arrive 4 ms apart.
Reversed delivery swaps which finger arrives first. The mixed-rate cases render
frames both before and after the trailing update. A scheduling self-check also
tests a 6 ms display phase. Every trace returns to its starting position.
Additional cases cover subpixel movement and pauses, zoom limits while panning,
coincident touches, and cancellation or replacement of either finger before every
touch has lifted. These edge cases check both rendered frames in the response
allowance. Zoom-limit controls reject a first-frame jump even when the second
frame is correct. Ownership tests use the same frame checks, including frozen
object geometry. Pauses and cancellation waits check every display frame
throughout the full 200 ms interval; temporary drift fails even if it recovers.

The frame oracle checks coherent samples after their real updates arrive. On an
ambiguous first frame it requires the previous stable view, rejecting temporary
zoom caused by a half-updated pair. It allows at most one extra display frame;
new input cannot extend an older response deadline. The 4 ms delivery skew is a
fixture setting, not the response budget. No-op events do not establish that both
fingers moved. Final frames drain the response allowance.

Stationary-finger traces independently check the rendered canvas point beneath
that finger. A continuous pan/pinch/combined/pinch/pan trace checks transitions
without lifting either contact. Positive and negative harness controls verify
that bounded stable delay passes while zoom pulses, anchor drift, excessive
delay, and locked gesture components fail.

Each `touch-replay` line reports the maximum rendered landmark error in logical
pixels and its timestamp. Any deviation from the permitted stable motion path
fails the test; the tolerance only covers floating-point rounding. Failure output
includes the arrived positions and expected and actual transforms.
Negative controls verify that intermediate zoom, sideways jumps, stalled motion,
overshoot, and failure to converge after the deadline fail even when endpoints are
correct. Every input event also checks that the transform stays finite and positive.

These are Flutter pointer tests running in Chrome. They do not exercise Android's
browser-to-Flutter event delivery or measure device frame performance. A recorded
device trace or an explicit filtering policy is still needed to distinguish
natural hand-motion jitter from correct response to separately received updates.

## TODO

a vague list

- self host docker image
- more comprehensive file switching support
- LSP integration
- better media player support for videos etc
- perf issues on draw
