# Media link cards

Status: active

## Goal and scope

Complete URL-derived image and link rendering, shared media interactions, and
consistent external URL validation at every input and transfer boundary. The
accepted [decision](../adr/0003-media-link-cards-without-embeds.md),
[interaction model](../specs/interaction-model.md), and
[architecture](../arch/ownership.md) define the contract.

## Non-goals

Do not add a saved media kind or automatic mode, remote image probing, playback,
iframe embeds, arbitrary-site metadata requests, scraping, a proxy or backend,
downloaded previews, or another media transfer format. Do not rewrite existing
browser data or add a compatibility layer for the superseded display-kind form.

## Design

Media elements save their source URL and geometry. Local attachment references
use the existing path checks. A valid HTTPS URL is an image only when its path
ends in `.png`, `.jpg`, `.jpeg`, `.gif`, or `.webp`, ignoring case and excluding
query and fragment text. Other valid HTTPS URLs render as links. Extensionless
remote images intentionally remain generic cards; upload or paste bytes to add
an image instead.

Use one pure URL policy in `document/media_url.dart` for URL editing, plain-link
paste, serialized clipboard data, project import, and library restore. Reject
unsafe or invalid new, edited, or imported URLs and URLs longer than 2048
characters. Preserve already stored arbitrary browser strings without rewriting
them, but never load or open invalid legacy sources. Do not tighten the global
document decoder. Reject invalid import candidates before attachment staging or
publication, leaving the current document, history, and attachments unchanged.

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

- [x] Update the accepted behavior, ownership, and persistence contracts for the
  revised URL-derived design.
- [x] Remove the Image/Link selector and saved display kind; derive image versus
  link from attachment validation or the supported URI path suffix.
- [x] Share tap, drag, cancellation, device filtering, sizing, and resize
  animation in one private media body without changing content rendering or
  resource ownership.
- [x] Centralize URL validation and apply it to editing, plain-link paste,
  serialized clipboard data, project import, and library restore. Reject invalid
  imported sources before staging or publication.
- [x] Preserve the provider metadata pipeline and card footprints without
  probing other links.
- [x] Test path suffixes with query/fragment, extensionless and unsupported
  URLs, empty and invalid legacy values, all URL ingress boundaries, failure
  atomicity, media gestures, and provider metadata lifetime behavior.

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

- [x] Run focused Chrome tests for URL policy, every input/import boundary,
  provider behavior, and failure atomicity.
- [x] Run `flutter analyze` and `flutter build web`.
- [x] Run the full Chrome suite after the revision is complete: 646 passed,
  4 skipped. The subsequent standard web build passed; the existing
  `isolate_contactor` Wasm dry-run warnings remain.
- [x] Check documentation link targets and `git diff --check` for this revision.

Revised-build Chromium smoke checks confirmed no Image/Link selector, a generic
card for an extensionless URL with no resource request to its destination, direct
`.jpg` image rendering, and enriched YouTube metadata. Static inspection confirms
one resolved-media drag implementation and resize handle in `_MediaBody`.
