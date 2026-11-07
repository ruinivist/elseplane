# Render media links without embedded players

Status: accepted

Date: 2026-11-07

## Context

Canvas media needs to support images and useful link cards without adding
embedded players, arbitrary-site scraping, or another saved-media format.
Provider data and thumbnails are remote, variable, and not part of the canvas's
durable content. A single source URL should determine whether a media block
shows an image or a link card; users do not need a saved display mode.

The canvas organizes references rather than long-form viewing. Users open the
destination to consume videos or other content instead of watching in a small
canvas block.

## Decision

Media elements save their source URL and geometry, not a display kind or an
automatic mode. Local attachment references continue to use the existing
attachment-path checks. For an external URL, render an image only when its
`URI.path` ends in `.png`, `.jpg`, `.jpeg`, `.gif`, or `.webp`, without regard to
case; query and fragment text do not affect the path suffix. Every other valid
HTTPS URL is a link. Do not probe remote content to infer its type. An
extensionless remote image is a link card; users can upload or paste image bytes
to create a local image instead.

Accept new and edited external sources only when the shared policy deems them
safe, valid HTTPS URLs no longer than 2048 characters. Use one pure URL policy
in `document/media_url.dart` for the URL field, plain-link paste, serialized
clipboard values, project import, and library restore. It has no widget, network,
or storage dependencies. Reject unsafe or invalid external candidates before
staging or publishing them, without changing the current document, history, or
attachments. Keep the document
decoder permissive for already stored browser data: arbitrary legacy source
strings remain readable and are not rewritten, but invalid sources show the
unresolved URL panel and are never loaded or opened. Do not migrate or add a
compatibility path for a saved display-kind field.

An empty source or unresolved legacy source keeps the URL panel visible. Device
image selection and pasted image bytes create local image attachments. Committing
a changed URL applies the derived rendering rule; invalid drafts are not saved,
requested, or opened.

Links use one shared card and one shared loader/parser that returns a normalized
metadata model. Rich metadata is best-effort and initially comes only from
public CORS-enabled oEmbed endpoints for YouTube, Vimeo, Spotify, and SoundCloud.
Match exact allowlisted hosts; do not fetch metadata for unknown sites. Use
provider-specific canonical request URLs, removing unrelated query parameters
and fragments. Enforce finite URL and metadata size limits, accept only bounded
plain-text metadata and validated HTTPS thumbnails from allowlisted hosts, and
ignore returned HTML. Use a five-second timeout with no retries. Start requests
only when a card is visible and retain source-keyed runtime resources across
culling. Ignore results for a changed source, removed card, or replaced document.

Provider cards have a default 480 by 360 footprint; generic links use 480 by 112.
Keep each footprint fixed through loading and failure. Metadata must not change
saved geometry or create history entries. Use the same card components and
transform behavior for providers. Do not add provider-specific widgets or custom
transforms.

An inactive link card activates on click and moves on drag, like an image; its
body does not navigate. The active card exposes an accessible Open link action
that opens the original URL in a new tab. Show launch failures. Generic cards
display host and path without query or fragment, while preserving the complete
original URL for saving and opening.

Only recognized YouTube, Vimeo, Spotify, and SoundCloud links use the shared
metadata pipeline; all other links remain generic cards and receive no network
or image-type probe. Provider metadata and thumbnails remain runtime-only and
are never written to canvas JSON or ZIP exports. Local image bytes remain
separate attachments under the existing media-storage decision. Link cards do
not play media.

## Alternatives

Iframe players are rejected because they consume canvas space, compete for
gestures and focus, and retain provider resources through view lifecycles.
Universal scraping, proxying, or a backend service would request arbitrary sites
or add infrastructure and privacy costs. A persisted display kind or remote
image probing would duplicate information or add requests that do not establish
reliable image support. Separate provider widgets and custom transforms duplicate
shared card behavior.

## Consequences

Provider cards depend on third-party availability and may show generic host/path
content when a request or thumbnail fails, without changing their footprint.
Provider requests disclose the canonical media URL to that provider, and
thumbnail loads contact their validated third-party hosts; unknown sites receive
no metadata request. Extensionless remote images intentionally appear as generic
links, and invalid legacy sources remain unresolved until the user replaces them.
Metadata and thumbnails are unavailable offline and are not retained after the
runtime resource lifetime ends. The feature does not provide playback.
