# Media link cards

Status: active

## Goal and scope

Complete URL-derived image and link rendering, shared media interactions, and
raw source preservation with use-time resolution. The
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
link-card content distinct. Link content adds only its keyboard and semantics
wrapper. Retain source-keyed resource lifetimes and the shared provider loader:
only exact YouTube, Vimeo, Spotify, and SoundCloud hosts receive metadata
requests; every other link remains generic and receives no network or image-type
probe. Preserve the fixed 480 by 360 enriched-provider and 480 by 112 generic
link footprints, five-second timeout, bounded metadata, and runtime-only
metadata and thumbnails.

## Checklist

- [x] Update accepted behavior, ownership, persistence, and UI contracts for raw
  source strings and runtime-only resolution.
- [x] Remove document-source validation while preserving structural and
  attachment validation on every transfer path.
- [x] Resolve external sources only at use time for classification, image loads,
  provider matching, card display, and link opening.
- [x] Keep source editing exact and recognize plain-link clipboard content
  without inserting ordinary text.
- [x] Verify raw-source edit/open/undo, bare provider/image resolution,
  clipboard paste, serialization/import roundtrips, and inert unsupported
  sources; preserve real transfer failure checks.
- [x] Run focused Chrome tests, `flutter analyze`, and `flutter build web`.

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
- [ ] Run the full Chrome suite (lead-owned verification).
- [x] Check documentation links and `git diff --check`.
