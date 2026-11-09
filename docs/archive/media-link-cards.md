# Media link cards

Status: complete

Superseded 2026-11-09: The original click-to-open-on-every-body-click behavior
below was replaced by the accepted inactive-activates / active-opens behavior in
the [interaction model](../specs/interaction-model.md) and
[ADR 0003](../adr/0003-media-link-cards-without-embeds.md). Historical checks
below describe the earlier behavior; the final revision note records current
checks.

## Goal and scope

Complete URL-derived image and link rendering, shared media interactions, raw
source preservation with use-time resolution, and the accepted combined
link-body activation and navigation behavior. The
accepted [decision](../adr/0003-media-link-cards-without-embeds.md),
[interaction model](../specs/interaction-model.md), and
[architecture](../arch/ownership.md) define the contract.

## Non-goals

Do not add a saved media kind or automatic mode, remote image probing, playback,
iframe embeds, arbitrary-site metadata requests, scraping, a proxy or backend,
downloaded previews, or another media transfer format. Do not rewrite existing
browser data or add a compatibility layer for the superseded display-kind form.

## Design

Media elements save raw source strings and geometry. Local attachment references
use the existing path checks. A resolved external HTTPS URI is an image only
when its path ends in `.png`, `.jpg`, `.jpeg`, `.gif`, or `.webp`, ignoring case
and excluding query and fragment text. Other usable HTTP(S) sources render as
links. One pure editor resolver normalizes a copy at use time; edits and all
clipboard/project/library transfer paths preserve raw text. Unusable sources
stay unresolved and are never requested or opened. Extensionless remote images
remain generic cards; upload or paste bytes to add an image instead.

Plain-text canvas paste uses a compact explicit-HTTP(S)/protocol-relative or
link-like address heuristic, but stores the original clipboard text. Ordinary
text is not inserted. No external-media URL validation is added to document or
transfer decoding; structural, archive, and attachment validation remain.

Use one private media body for common tap, drag, cancellation, device filtering,
sizing, and resize animation. Keep image clipping and selection borders and
link-card content distinct; `MediaLinkCard` remains pure presentation. `_MediaBody`
owns existing gesture handling and the link-body pointer cursor. `MediaElementView`
state owns one `_openLink` action, passed to both the active card's explicit
button and the body's combined activation. `CanvasView` binds that activation
through the existing `CanvasInputTarget`: extend its activation path with an
optional callback that runs only after lifetime, tool, modifier, and blocked
guards accept activation, and ensure Select and Space-panning guards apply
before the external action. `MediaElementView` receives one combined activation
callback rather than independently activating and launching; activation may be
vetoed. CanvasInput remains responsible for selection, cancellation, and
auto-layer promotion. Launch immediately from the resolved destination without
awaiting metadata or another network request or rewriting raw source text.

Preserve existing drag/group movement and ensure canceled, modified, blocked, or
stale interactions do not launch. Body clicks on already-active cards still
attempt opening. Keep URL fields and buttons from bubbling to body navigation;
Enter in the URL field remains commit-only. Focused-card Enter/Space and
semantics activation use the combined action, without repeated launches from key
repeat. Do not add click timers or double-click suppression: each recognized
body click may launch once. Preserve launcher failure reporting and activation
state; do not add popup-block detection promises or navigation fallbacks.

Retain source-keyed resource lifetimes and the shared provider loader: only exact
YouTube, Vimeo, Spotify, and SoundCloud hosts receive metadata requests; every
other link remains generic and receives no network or image-type probe. Preserve
the fixed 480 by 360 enriched-provider and 480 by 80 generic link footprints,
five-second timeout, bounded metadata, and runtime-only metadata and thumbnails.

## Completed URL-derived media baseline

These completed checks cover URL-derived rendering and the explicit Open link
action. They do not verify the newly accepted body-click activation and
navigation behavior below.

- [x] Update accepted behavior, ownership, persistence, and UI contracts for raw
  source strings and runtime-only resolution.
- [x] Remove document-source validation while preserving structural and
  attachment validation on every transfer path.
- [x] Resolve external sources only at use time for classification, image loads,
  provider matching, card display, and the explicit Open link action.
- [x] Keep source editing exact and recognize plain-link clipboard content
  without inserting ordinary text.
- [x] Verify raw-source edit/explicit-open/undo, bare provider/image resolution,
  clipboard paste, serialization/import roundtrips, and inert unsupported
  sources; preserve real transfer failure checks.
- [x] Run focused Chrome tests, `flutter analyze`, and `flutter build web`.

## Combined link-body click implementation

Implementation stays in `lib/canvas/editor/elements/media/media_element_view.dart`,
`lib/canvas/editor/canvas_view.dart`, and `lib/canvas/editor/canvas_input.dart`.
No resource, document, or shared card-layout changes are required.

- [x] Implement the ownership and callback flow described above without changing
  media source, persistence, or metadata ownership.
- [x] Extend `test/canvas/editor/elements/media/media_element_test.dart` and
  `test/canvas/editor/canvas_input_test.dart`
  for generic and provider cards: one accepted open plus activation when
  inactive and already active; activation retained after launcher failure; raw
  resolved destination; and no navigation from the URL field or explicit button
  bubbling.
- [x] Cover drag and canceled gestures, Ctrl/Cmd selection, Space panning,
  non-Select tools, blocked/stale targets, overlapping mouse/stylus pointer
  rejection, source change/removal/document replacement, selection and auto-layer
  promotion, focused-card Enter/Space and semantics activation, key repeat, and
  unchanged image/unresolved behavior. The regression first reproduced the
  rejected stylus tap opening its card while a mouse pointer remained down; it
  passes with the pointer-origin eligibility guard.
- [x] Run the focused Chrome tests, `flutter analyze`, and `flutter build web`.
  Focused media and canvas-input tests passed; analyze passed; standard web build
  passed with the existing Wasm dry-run `dart:html` incompatibilities in
  `isolate_contactor`.
- [x] In a real browser, verify one new tab for one completed body click and no
  tab for drag, modified click, or URL-field interaction. Do not rely only on a
  mocked launcher or assert that the browser switches focus.
  Chromium verification used a local HTTP destination: inactive and already-active
  body clicks each opened one tab and left controls available. Dragging,
  Ctrl-clicking, URL-field click/Enter, and Pen-tool Space panning opened no tab.
  The body reported a pointer cursor. This does not verify popup-block detection.
  After the pointer-origin correction, inactive and active clicks again each
  opened one tab; dragging and Ctrl-clicking opened none.
- [x] Run the full Chrome suite (lead-owned). Retain the documented
  popup-blocking limitation; do not add a dependency, platform/bootstrap change,
  or fallback. The final run passed 664 tests with 4 skipped in 4m40s after the
  pointer-origin correction.

Run focused tests with
`CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome test/canvas/editor/elements/media/ test/canvas/editor/canvas_input_test.dart`.
Run the full suite with
`CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome` and allow
at least ten minutes; the baseline suite took about four and a half minutes.

## Pre-revision evidence

The following evidence covers the earlier design with a persisted display kind,
manual override, and separate image rendering. It does not verify URL-derived
rendering, the shared media body, or the common URL policy and must not be used
as final-revision completion evidence.

From a local HTTP origin, the four public oEmbed sample requests returned HTTP
200, and their thumbnails loaded with `crossOrigin = anonymous`, decoded, and
were canvas-readable:

| Provider | Sample |
| --- | --- |
| YouTube | `M7lc1UVf-VE` |
| Vimeo | `76979871` |
| Spotify | `track/11dFghVXANMlKmJXsNCbNl` |
| SoundCloud | `forss/flickermood` |

Additional Chromium metadata probes returned HTTP 200 for Spotify album,
playlist, artist, and show samples. One episode sample failed to fetch; not all
resource shapes were verified against live providers. URL-shape tests covered
canonicalization and fallback independently of provider availability.

Integrated Chromium checks loaded a YouTube thumbnail and title and rendered a
generic host/path card without displaying its query or fragment. The earlier
validation also covered invalid-draft rejection, destination hostnames on
enriched cards, request abortion at the timeout, and failure not replacing the
saved card or thumbnail. Those tests and smoke checks predate this revision.

The earlier full checks reported `flutter analyze`, the full Chromium suite
(636 passed, 4 skipped), and `flutter build web` passing. The standard web build
succeeded; its Wasm dry run reported `dart:html` incompatibilities in
`isolate_contactor`. These results are pre-revision only; they do not establish
that the revised implementation passes.

## Verification

- [x] Run focused Chrome tests for media, editor session/history, clipboard,
  project/library transfers, workspace handoff/transfer, and attachment workflows.
- [x] Run `flutter analyze` and `flutter build web`. Standard web build passed;
  its Wasm dry run reports existing `dart:html` incompatibilities in
  `isolate_contactor`.
- [x] Run the full Chrome suite (664 passed, 4 skipped).
- [x] Check documentation links and `git diff --check`.

## State-dependent click revision (2026-11-09)

Focused media and canvas-input Chrome tests (102 passed), `flutter analyze`, and
`flutter build web` passed. The full Chrome suite passed with `--concurrency=1`:
664 passed, 4 skipped in 5m40s. Manual browser verification was waived; use Chrome
tests only. Both read-only reviews reported no findings.
