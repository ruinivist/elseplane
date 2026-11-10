# GitHub canvas MVP

Status: active planning; implementation not started

Date: 2026-11-09

This plan proposes GitHub connection, per-canvas commits, and single-canvas
imports. Implementation requires separate authorization. The accepted
[ownership contract](../arch/ownership.md),
[persistence contract](../arch/persistence.md), and
[interaction model](../specs/interaction-model.md) remain authoritative until
updated as part of implementation.

## Goal and scope

Connect the whole Elseplane library to one GitHub account, repository, and
branch. Commit individual canvases independently. Support public and private
repositories through the existing Go token mediator in `~/main/go-token-mediator`.

For example, editing Maths and Physics and clicking Commit current canvas
while Maths is open publishes only Maths and its referenced images. Physics
remains uncommitted. Switching canvases preserves the shared connection and
destination. Successful commits update only the selected canvas's tracking.

Opening from GitHub imports one selected canvas into the existing local
library. Logout ends GitHub access without deleting local or remote content.
All transfers are manual; there is no background synchronization.

## User tasks: backend and account setup

The user owns hosting, configuration, credentials, and deployment. Implementation
can proceed with mocked services before the backend is available.

| Task | Required outcome |
| --- | --- |
| Host the existing mediator | HTTPS service, assumed at `https://backend.elseplane.ruiny.de`; substitute the actual address consistently if different. |
| Configure infrastructure | DNS, TLS, reverse proxy, private credentials, persistent SQLite storage, and service operation using the mediator's existing deployment guide. |
| Register a GitHub OAuth App | Homepage `https://elseplane.ruiny.de`; callback `https://backend.elseplane.ruiny.de/oauth/github/callback`. |
| Configure frontend origin | `frontend_origin_url` is exactly `https://elseplane.ruiny.de`, without a trailing slash. |
| Configure frontend completion | `frontend_completion_url` is `https://elseplane.ruiny.de/?github=complete`. |
| Configure GitHub provider | Provider key `github`, GitHub authorization/token endpoints, private client credentials, registered callback, and `scopes: ["repo"]`. |
| Supply frontend configuration | Set the public `GITHUB_MEDIATOR_URL` build variable after the backend is ready. |
| Prepare acceptance repositories | One public and one private repository, initialized with a README and an existing writable branch. |
| Run live acceptance | Authorize the GitHub account and verify the workflows against both repositories. |

Use `https://github.com/login/oauth/authorize` and
`https://github.com/login/oauth/access_token` as provider endpoints. Retain the
mediator's other required configuration. Never put the client secret in the
frontend or source control.

The `repo` scope grants broad public/private repository permissions. Selecting
one repository inside Elseplane does not narrow that authorization. Additional
profile/email scopes are unnecessary for this MVP. See
[GitHub OAuth scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps).

Keep expiring access tokens enabled where available. The existing mediator
supports optional expiry and refresh tokens; frontend code must also accept
responses without an expiry field. See
[GitHub OAuth authorization](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps).

Backend provisioning, secret management, and deployment automation are outside
the implementation work.

## Implementation: connection, controls, and local state

### Minimal controls

Add a small floating panel at the bottom-left of the workspace, using existing
themed controls. Keep it inside the viewport and prevent its input from editing
the canvas underneath it. A UI redesign is outside scope.

Disconnected, show Connect GitHub. Connected, show:

```text
@account · owner/repository · branch
Commit current canvas
Open from GitHub
Repository…    Log out
```

Use functional dialogs for destination selection, remote browsing, and commit
confirmation. Disable duplicate operations and conflicting library actions
during transfers, and restore controls on every exit path.

### Connection and logout

Reuse the mediator endpoints:

| Action | Request |
| --- | --- |
| Connect | `POST /oauth/github/start` |
| Obtain access token | `POST /oauth/github/token` |
| Log out | `POST /session/logout` |

Every mediator POST includes cookies, `Content-Type: application/json`,
`X-OAuth-Bridge: 1`, and body `{}`. Handle responses that are not JSON and the
logout endpoint's empty `204` response.

1. Save completed local edits before OAuth navigation; stop if saving fails.
2. Start authorization and validate that the returned URL uses HTTPS and the
   expected GitHub authorization host/path before navigating.
3. On return, consume and remove the completion marker.
4. Obtain a token and verify the account through GitHub's user endpoint.
5. Restore the saved destination or request a repository. Never automatically
   commit after authorization.

Accept only `owner/repository`. Fetch its details, show its visibility, and use
its default branch. Do not parse repository URLs or offer branch selection.
Do not create branches or repositories; protected default branches may reject
commits.

Keep access tokens in memory and obtain a current token at the start of an
operation. Client secrets and refresh tokens remain with the mediator. GitHub
API requests go directly to `api.github.com` without mediator cookies. Never
log tokens, authorization codes, or raw token responses.

Logout clears in-memory credentials and calls the mediator logout endpoint.
Disable GitHub operations until reconnection. Confirm logout only after server
success; otherwise report failure and allow retry. Keep destination preferences
and canvas tracking so reconnecting the same account can resume. Explain that
logout ends the local session but does not revoke GitHub authorization.

No mediator runtime changes are expected. If existing tests lack coverage, add
a focused compatibility test for GitHub token responses with comma-separated
scopes and optional expiry.

### Local metadata and ownership

Persist optional non-secret metadata with the existing local library snapshot:

| Owner | Metadata |
| --- | --- |
| Library | Account ID, repository identity and owner/name, shared branch. |
| Canvas | Last confirmed remote path, document and referenced attachment blob SHAs, and local-to-remote attachment filename mapping. |

Existing libraries load without this metadata. Preserve it through ordinary
edits, renames, and moves, and ensure every library reconstruction preserves
the shared destination. Portable `.canvas` files and existing ZIP transfers
exclude connection metadata. Restoring a portable backup starts without a
GitHub destination or commit baseline.

Changing repository or account requires confirmation and resets all
canvas commit tracking while preserving local documents. It does not delete
anything from the previous repository. Verify account identity before reusing
a saved connection; a different account cannot silently reuse it.

Keep networking, orchestration, and feature UI in a small GitHub feature module.
Keep serialization and attachment preparation in the library transfer layer.
The workspace composes the feature and editor. Library code must not depend on
GitHub networking or editor internals. Reuse installed `http` and `web`
dependencies; add no dependencies.

Pass `GITHUB_MEDIATOR_URL` through local Make targets and CI builds. Hide GitHub
controls when it is unset. The variable contains only a public service address.

## Implementation: commit and open

### Repository layout

Mirror each committed canvas's local title and folder path:

```text
Maths.canvas
attachments/
  <image-id>.png
University/
  Physics.canvas
  attachments/
    <image-id>.webp
```

Each `.canvas` contains pretty-printed, existing versioned `CanvasDocument`
JSON. Append a `.canvas` suffix to the full local title; import removes that
final suffix. Its local image references remain
`attachments/<image-id>.<extension>`, relative to its own directory. Sibling
canvases share that directory's attachments folder.

Preserve spaces and Unicode names. Reject unsafe path segments and file/folder
collisions rather than silently sanitizing names. Reserve remote `attachments`
directories for images; explain a conflicting local folder name before upload.
Empty folders are not published. External URLs remain external.

### Commit current canvas

1. Save completed edits and capture the current canvas ID, immutable document,
   and folder path for the operation.
2. Confirm repository, branch, and old/new canvas paths without a per-file
   preview. Provide an editable commit message, prefilled with
   `docs: save canvas`; require a nonempty, short lowercase Conventional Commit
   subject and an explicit Commit click.
3. Read the latest branch head and tree. Check that tracked remote document and
   image blobs still match their last confirmed versions.
4. Prepare only the selected document and its referenced images.
5. Create a tree using the existing tree as `base_tree`, preserving unrelated
   repository content.
6. Create one commit whose parent is the captured branch head, then update the
   branch reference with `force: false`.
7. Persist only the selected canvas's new baseline and show its commit link.

This makes the document and images visible together. A concurrent branch update
must fail without overwriting intervening work. See the
[Git database workflow](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-your-git-database)
and [reference updates](https://docs.github.com/en/rest/git/refs).

Never serialize the whole library into an upload. Local saves may flush other
canvases, but their contents and commit tracking are excluded from the GitHub
operation. Other uncommitted canvases remain uncommitted.

A first publication requires an unused destination `.canvas` path. If occupied,
offer opening the remote canvas or choosing another local name. A linked
canvas can update only when its tracked remote files still match the baseline;
unrelated repository changes are retained.

After a local rename or move, create the new remote path and remove the old
linked `.canvas` path in the same commit. A folder rename moves only the
selected canvas remotely; siblings move when individually committed. Never
delete remote files merely because a local canvas was deleted.

Reuse identical attachment blobs. Never overwrite different image bytes at an
occupied path: allocate a fresh UUID filename and adjust only the outgoing
document. Preserve imported remote filenames through the stored attachment
mapping. Retain old images because other canvases may reference them. If paths
and blobs are unchanged, report No changes to commit without creating a commit.

On remote conflicts or concurrent branch updates, stop and preserve local work.
Offer opening the remote version as another local canvas. Do not automatically
merge, force-push, or retry writes.

If the final request has an uncertain outcome, report the commit as unconfirmed
and provide the branch link. Require checking/reopening the remote version
before another write. If GitHub succeeds but saving local tracking fails,
report those outcomes separately and preserve the commit URL.

### Open a selected canvas

1. Capture a remote commit and fetch one recursive tree from the shared
   repository/branch. Filter regular `.canvas` files for selection.
2. Select a regular `.canvas` file and fetch its JSON and only its referenced
   sibling attachments from that snapshot.
3. Validate the complete candidate before changing local state.
4. Recreate the remote parent folders locally, reusing matching folders.
5. Stage images at fresh local paths with the existing import mechanism.
6. Save added folders, canvas, remapped references, and tracking in one library
   write, then open the imported canvas.

If the local canvas name is occupied, ask for another name. If a canvas blocks
a required folder path, stop and explain the collision. Never implicitly
replace another local canvas.

Reject truncated tree responses with a clear unsupported-repository-size
message; do not add lazy browsing or a fallback traversal. Fetch content by
blob SHA so branch changes cannot mix file versions. Reject symlinks and
unsupported Git object types. See the
[GitHub tree API](https://docs.github.com/en/rest/git/trees).

Reuse document decoding, attachment discovery, image validation, reference
rebasing, and import staging. Preserve existing 10 MiB image and 140 MiB canvas
limits, and check GitHub's additional per-blob limit before upload. Do not
download external media URLs during transfers. Failed imports preserve the
library and clean up only newly staged images. See the
[GitHub blob API](https://docs.github.com/en/rest/git/blobs).

Give actionable messages for reconnection, insufficient scope, missing
repository/branch, write permissions, organization restrictions, protected
branches, invalid files, conflicts, network failures, and rate limits. Honor
retry timing without automatically retrying uncertain writes.

## Implementation checklist

- [ ] Add the bottom-left panel, OAuth connection, shared destination, logout,
  and build configuration.
- [ ] Add optional local metadata and preserve it across library operations.
- [ ] Add remote browsing and staged single-canvas import.
- [ ] Add per-canvas atomic commits, attachment mapping, and linked moves.
- [ ] Add failure handling and focused regression tests.
- [ ] Update accepted ownership, persistence, and interaction documents to
  describe implemented behavior.
- [ ] Complete local checks and hand over live acceptance to the user.

Use `/home/zero/worktrees` for any implementation worktrees. Use short lowercase
Conventional Commit subjects. Backend deployment remains a user task.

## Verification

Use injected HTTP clients and fake stores for deterministic behavior/failure
tests. Cover:

- Committing Maths excludes uncommitted Physics changes and images, and does
  not update Physics's commit tracking.
- Switching canvases preserves the global destination; destination/account
  changes clear tracking without changing documents or remote files.
- Repository entry accepts `owner/repository` and uses the default branch;
  truncated tree responses fail clearly without a partial file list.
- The entered commit message reaches GitHub unchanged; empty or invalid
  subjects prevent submission.
- OAuth headers, completion, expired sessions, missing scope, logout success,
  and failed logout.
- Root/nested paths, spaces, Unicode, local name collisions, shared images,
  and unchanged imported image filenames.
- One remote commit contains document/images and preserves unrelated files.
- Rename/move removes only the selected canvas's old `.canvas` path.
- Invalid documents, unsafe paths, symlinks, missing images, and size limits.
- Import rollback on attachment or metadata persistence failure.
- Remote content changes, branch races, protected branches, duplicate clicks,
  uncertain writes, and tracking-save failure after remote success.
- Existing browser saves and ZIP transfers remain functional.

Run focused browser tests with
`CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome <test-file>`.
Run `flutter analyze`, `flutter build web`, and the full Chrome test suite before
committing feature work. Run mediator tests for any mediator changes.
Documentation-only work needs diff and link checks.

Live acceptance requires the deployed mediator and both test repositories:

1. Connect and select the shared destination.
2. Edit two canvases; commit one and verify the other is absent or unchanged.
3. Commit root/nested canvases with images and verify sibling attachments.
4. Import a selected canvas without replacing existing local canvases.
5. Edit/recommit, then rename/move and verify the remote file move.
6. Change the remote canvas independently and verify overwrite is refused.
7. Repeat against the private repository, then log out and verify operations
   require reconnection.

## Deferred work and limits

Defer whole-library sync, bulk commits, automatic uploads, merging, pull
requests, repository/branch creation, remote deletion on local deletion, and
attachment garbage collection. Also defer repository URL parsing, branch
selection, per-file commit previews, and lazy repository browsing. Keep one
shared destination for the MVP; repositories with truncated trees are unsupported.

Live credentials, hosting, and end-to-end OAuth remain unverified. OAuth `repo`
access is broad, browser-held tokens are exposed to malicious frontend scripts,
and unused remote images accumulate until cleanup is designed.
