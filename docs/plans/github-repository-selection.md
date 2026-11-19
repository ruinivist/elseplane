# GitHub App repository selection

Status: active; token compatibility is complete, while discovery and live
verification remain open.

## Goal and scope

Replace broad GitHub OAuth App repository access and typed `owner/repository`
entry with a GitHub App installation and repository dropdowns. Users can
authorize multiple existing repositories on personal accounts and organizations,
then choose which repository receives a manual canvas commit or supplies an
import. Require a repository with at least one commit.

The accepted [interaction model](../specs/interaction-model.md), [transfer
specification](../specs/folder-based-canvas-transfers.md), and [transfer
design](../arch/folder-based-canvas-transfers-design.md) now define the target
behavior. Preserve the existing [ownership](../arch/ownership.md),
[persistence](../arch/persistence.md), and [UI](../arch/ui.md) boundaries. This
plan does not override accepted contracts.

There are no deployed users to migrate. Do not add old OAuth App support,
dual authentication modes, legacy token handling, migration code, or automatic
browser-data resets. Do not change unrelated transfer work tracked in the
[folder-based transfer plan](folder-based-canvas-transfers.md).

## Fixed product decisions

- The GitHub App is owned by a personal account and installable on any account.
  Request Contents read/write and required Metadata read-only, with no account
  or organization permissions. Use expiring GitHub App user access tokens
  through the existing mediator OAuth flow; do not require a `repo` scope.
- GitHub's installation screen controls repository authorization. It can grant
  several selected repositories or all repositories. Elseplane's dropdown
  controls the current destination; selecting another destination does not
  change the GitHub grant.
- List only repositories returned for accessible installations of this app,
  not all repositories accessible to the user through a broad repository API.
  Do not accept arbitrary repository text or offer repository creation.
- Keep one remembered destination per local library, shared by Import and
  Commit. The list of authorized repositories belongs to the GitHub feature,
  not the library. Do not introduce per-canvas repository links.
- Show one searchable repository dropdown in the repository setup dialog after
  connecting. Once confirmed, display `owner/repository`, visibility, and the
  default branch beside the existing Import and Commit actions. "Change
  repository" reopens the same setup dialog. Import and Commit never ask for a
  repository again; the commit dialog displays the selected destination.
- Filter the picker by owner/name without interpreting typed search text as a
  repository destination. Setup selection is a draft until confirmed: cancel
  leaves the saved destination unchanged, and confirmation validates and saves
  the selected destination. A save failure does not publish the new selection.
  Import and Commit do not change the saved destination.
- Preselect the same-account saved repository only when it is still in the
  authorized list. If there is exactly one candidate and no saved selection,
  show it as the setup-dialog default, but do not start a transfer automatically.
  Never silently replace an inaccessible saved repository with another one.
- Read-only repositories remain available for import. Disable commit when the
  user lacks push access or the repository is archived/disabled. GitHub remains
  authoritative about branch rules and current permissions.
- Empty repositories remain discoverable. Selecting one shows:
  "This repository is empty. Add a README on GitHub, then refresh."
  Block Import and Commit; upload no files and create no branches or commits.
- Keep installation IDs and tokens in memory only. Persist the existing
  account/repository destination shape; do not persist installation IDs or add
  an authorization cache. Before each transfer, look up membership only in the
  selected installation and independently verify account/repository identity
  and default branch.
- Keep manual actions, current-canvas commits, whole-repository additive imports,
  default-branch-only transfers, explicit commit messages, and no automatic
  write retry. No branch selector, pull-request workflow, synchronization,
  repository initialization, private keys, webhooks, or new dependencies.

## Source baseline

Pre-implementation source baseline inspected 2026-11-15; recheck current symbols
and working-tree scope during execution.

| Component | Current behavior | Planned change |
| --- | --- | --- |
| `lib/github/github_api.dart` | Requires `repo` scope; fetches typed repository; bounded REST transfer implementation | Accept GitHub App token responses; discover installation repositories; resolve selected repository access and reject empty repositories. Keep existing commit publication. |
| `lib/github/github_controller.dart` | In-memory account, busy state, reconnect and logout retry | Also own installation/repository discovery state and refresh; clear it on account loss/logout. |
| `lib/github/github_panel.dart` | Typed repository dialog, fixed-repository commit dialog, panel actions | One searchable setup dropdown, selected-repository display, change/access-management actions. Keep the fixed-repository commit dialog. |
| `lib/github/github_workspace_panel.dart` | Saves before OAuth; selected destination and transfer orchestration | Compose discovery, selection persistence, confirmations, access navigation, and existing transfer callbacks. |
| `lib/github/github_browser.dart` | Separate cookie-enabled mediator client; validated OAuth navigation and GitHub links | Preserve those boundaries; open validated installation/access-management links separately from OAuth. |
| `lib/app/app.dart`, `lib/app/workspace.dart` | Creates configured GitHub API and passes feature callbacks | Pass one public GitHub App slug through composition; do not move GitHub state into Workspace. |
| `lib/library/github_metadata.dart`, `library_controller.dart` | Strict non-secret `GitHubDestination` and queued destination save | Reuse unchanged destination shape and save operation; no new persistence fields. |
| `Makefile` | Passes `GITHUB_MEDIATOR_URL` for run/release/build | Also pass public `GITHUB_APP_SLUG` consistently; preserve local ignored overrides. |
| Sibling `go-token-mediator` repository | Generic protected OAuth code/PKCE, SQLite sessions, refresh, token endpoint | Verify existing relevant protocol tests and keep runtime architecture/routes. Add a test only for a demonstrated coverage gap. |

## Architecture and interfaces

### Authentication and installation

Use GitHub App user access tokens, not installation access tokens. The mediator
keeps the client secret and refresh token; Elseplane receives an access token in
memory and calls GitHub directly. Do not require the OAuth `repo` scope or infer
access from a scope header. A token's effective access is the intersection of
the app installation's permissions/repositories and the signed-in user's access.

Keep the existing endpoints and empty JSON browser requests:

1. `POST /oauth/github/start` creates protected pending authorization.
2. Navigate only to the validated GitHub OAuth authorization URL.
3. The mediator validates state and exchanges the code at its existing callback.
4. The frontend consumes `github=complete` and verifies `/user`. After the
   API/controller slice lands, one discovery operation lists accessible
   installations and their repositories.
5. `POST /oauth/github/token` supplies current access tokens and refreshes them
   on the backend as needed. Logout remains `POST /session/logout`.

Remove `repo`-scope requirements and scope-header-based permission diagnosis,
including the obsolete `insufficientScope` error path and its callers. Accept
empty or omitted scope with the existing response type validation. Do not infer
authorization from a token prefix or replace authorization with a scope check.
Keep 401 as reconnect; distinguish permission denial, missing resources, rate
limits, conflicts, and uncertain remote publication.

Use one required public `GITHUB_APP_SLUG` when the GitHub feature is configured.
Validate it and construct `https://github.com/apps/<slug>/installations/new`;
never put credentials in build defines. Tests inject app configuration and
navigation callbacks through the existing composition pattern.

Keep GitHub's "Request user authorization during installation" unchecked and
the setup URL blank. Connect performs the normal protected OAuth flow. Once
connected, "Manage repository access" opens a separate GitHub tab:

- Install/add another account: the app installation URL.
- Manage an existing account: that installation's validated GitHub `html_url`.
- With multiple installations, show the account choices in an access-management
  dialog; do not guess which installation the user wants to change.

Elseplane stays open and offers an explicit Refresh action after changes. No
installation callback, new completion marker, automatic tab-focus refresh, or
installation-ID trust shortcut is needed. Installation approval does not count
as user authentication. Finish interactions and save completed edits before
external navigation; do not navigate if saving fails.

Assume local browser saves are fast: open access-management links directly
after saving; do not add confirmation dialogs, popup detection, or fallback UI
for hypothetical slow saves. Preserve save-failure handling.

### API discovery and repository resolution

Keep the following values and operations in `lib/github/github_api.dart`:

- `GitHubInstallation`: installation ID, account ID/login, validated management
  URL, and Contents permission needed for action availability.
- `GitHubRepository`: installation ID, repository ID, canonical owner/name,
  visibility, default branch, user permissions, and archived/disabled flags.
- One public `discoverRepositories()` operation returning a record of
  `installations` and `repositories`. It uses one token and a 60-second overall
  deadline. Keep the paginated installation and repository request helpers
  private; do not expose unused public listing methods.
- `resolveRepository(repository)`: verify current account, installation
  membership, repository ID, current permissions, canonical name, default
  branch, and nonempty branch state; return a `GitHubDestination`.
- Keep the existing transfer entry points, adding the selected installation as
  explicit operation context:
  `readRepository(destination, installationId: ...)` and
  `commitTransfer(destination, tree, installationId: ..., message: ...)`. Both
  require the named `installationId`; it is a lookup context, not proof of
  access.

Use one token per discovery operation, request `per_page=100`, and construct
each next-page request on the fixed GitHub API origin. Do not follow arbitrary
response URLs with credentials. Validate page envelopes and fields, terminate
pagination from the provider's pagination metadata, deduplicate by repository
ID, and sort by full name. Build a complete fresh result before publishing it;
a failed page must not masquerade as a complete list or remove a saved choice.
Retain finite response bounds and add a 60-second overall discovery deadline
in addition to the existing 15-second per-request timeout. A deadline failure
offers explicit retry, not a truncated selectable result.

Do not use repository byte size as an emptiness test. On selected-repository
resolution and immediately before a transfer, verify the default-branch head.
For a missing head, distinguish a repository without any branches from a
missing/default-branch inconsistency using a bounded branch query. Map only
confirmed empty repositories to the README message; do not reinterpret generic
401/403/404/409 failures as emptiness. Verify GitHub's exact empty-repository
responses in the early live protocol check and use those cases in tests.

Recheck installation membership before Import/Commit so a saved destination
cannot bypass the app-authorized list, including for public repositories. Keep
this check inside the API transfer verification helper: query only the selected
installation's repository pages until the selected repository ID is found, or
reject it after the complete search. The selected in-memory
`GitHubRepository` supplies the required installation ID. Reuse the private
paginated request helpers with that operation's token; do not enumerate
unrelated installations, add an authorization cache, or persist installation
IDs. A lookup failure fails closed rather than falling back to a public
repository request. After reload, resolve saved account/repository IDs against
discovery before enabling transfers; do not guess an installation for a saved
destination.
Preserve the existing same-account and immutable repository-ID checks inside
both transfer entry points. Reject a changed default branch and require refresh
and explicit confirmation rather than publishing to a different branch.

### State, UI, and data flow

`GitHubController` owns account, installation/repository lists, discovery
loading/error state, and logout retry. Discovery failure does not log out a
valid account unless the error is a real authentication failure. On logout or
account change, clear old account-scoped lists. Ignore results delivered after
disposal or replacement of the account/request. Keep one active controller
operation; do not introduce a cache service or background refresh loop.

Check the mediator session once when the configured feature mounts, including
when no destination has been saved. Treat an expected missing session as
disconnected without an error banner. This avoids losing a connected account
on reload before its first repository selection. After account verification,
load discovery results independently so a discovery failure has a retry action
without forcing another login.

Keep the single setup picker feature-local in `github_panel.dart`; use Flutter's
existing dropdown/search controls and existing surface/dialog components.
Provide keyboard selection, accessible labels, bounded scrolling, loading,
refresh/retry, and no-access states. No new app-wide picker abstraction.

`GitHubWorkspacePanel` owns the setup-dialog draft, explicit selection confirmation,
destination saves through `LibraryController`, and transfer orchestration.
Workspace continues to supply the shared transfer interlock, editor interaction
finishing, immutable canvas capture, and provider-neutral import callback.
Library and editor code never fetch installation/repository data.

For repository setup/change: finish interaction, acquire the interlock, flush
completed edits, show the setup dialog, resolve the chosen repository, and save
the explicit choice. Cancel means no destination save and no remote write.

For Import/Commit: finish interaction, acquire the interlock, flush completed
edits, capture the already selected destination and its installation ID, and
call the transfer API. Import retains the existing shared merge/collision
confirmation; there is no new repository-selection or import dialog. For
Commit, capture the current canvas after flush and before the existing
message/confirmation dialog as today. Keep the canvas, destination, and
installation ID fixed for the operation. Canceling the commit dialog means no
remote write. Neither transfer saves or changes repository selection. Release
the interlock in `finally`. Hold the existing controller busy state around
network work without nesting its `run` operations.

Import stays additive through the existing callback. Commit keeps structural
path validation before blob uploads, one tree on the fresh head, one commit,
and one force-disabled reference update. Never create files, commits, or refs
to work around an empty repository. Preserve uncertain-write reporting and
links without retries. Access revoked after confirmation is a transfer error,
not permission to select a different destination.

## Configuration and setup

The personal GitHub App and selected-repository installation have been reported
as configured. Execution must verify settings without displaying secrets.

- Local mediator provider `github`: GitHub App client ID/secret, existing OAuth
  endpoints and `https://localhost:3003/oauth/github/callback`, and `scopes: []`.
- Frontend origin remains `https://localhost:3002`; mediator completion remains
  `https://localhost:3002/?github=complete`.
- Frontend local defines: `GITHUB_MEDIATOR_URL=https://localhost:3003` and the
  public `GITHUB_APP_SLUG`. Obtain the slug from the app's public URL; never
  derive it from a client secret or guess it from the display name.
- App settings: expiring user tokens enabled, device flow disabled, automatic
  user authorization during installation disabled, setup URL blank, webhook
  inactive, Contents read/write and Metadata read-only, installable on any
  account.
- Local credentials, certificates, session database, and ignored overrides stay
  local. Do not force-add ignored configuration or change the generic mediator
  example into an Elseplane-specific default.

Add a tracked GitHub setup playbook with placeholders and links, not real
credentials. The ignored local mediator README cannot be the only setup guide.
Update the documentation map and development-playbook link. Production hosting,
deployment, production credentials, and public callback setup are outside this
local implementation scope. No old-grant cleanup or session migration work.

The existing deployment build passes the public `GITHUB_APP_SLUG` repository
variable, defaulting to `elseplane-app`, alongside the mediator URL. This wiring
prevents a missing-slug startup error; it does not deploy the change or configure
production credentials and callbacks.

## Progress

- Contract alignment and the tracked setup playbook are complete.
- Minimal token compatibility: focused Chrome tests (24 tests) and
  `flutter analyze` passed. Existing mediator `go test ./...` passed.
- API/controller discovery and transfer checks: 34 focused Chrome tests passed.
  UI callers still require integration with the new transfer signatures.
- Protected sign-in returned to Elseplane as `@ruinivist`; the completion marker
  was consumed and a fresh cookie-only test checkpoint was saved after human
  account confirmation. Repository discovery and transfer protocols are not yet
  verified live.
- UI integration is implemented: 45 GitHub tests and 15 workspace tests passed;
  `flutter analyze` and a web build with both public values passed. The full
  Chrome suite passed with 752 tests and 4 existing appearance tests skipped by
  disabled feature flags. The initial suite command exceeded its two-minute
  command limit; a rerun with a longer limit completed successfully.
- Both independent read-only reviews completed without findings. No findings
  were rejected, deferred, or skipped. The reviewed code scope is unchanged;
  these progress notes were updated after review.
- Live verification completed for the available private sandbox: session restore
  before selection, discovery, search/no matches, setup cancellation, explicit
  selection, refresh, access-chooser cancellation, import cancellation, and
  importing seven canvases. Transfers used the displayed saved destination
  without reopening the repository picker.
- A single explicit sandbox commit was reported successful by the app:
  `bcb50062ea7a7643f7b9bc11510ba862f2e52492`. Its private GitHub result page was
  not viewable in the test browser, so independent commit-page verification is
  unavailable; no submission was retried. The owned browser/debug run was stopped.
- Only one authorized repository was available. Multiple-repository,
  multiple-installation, empty-repository, and permission-change cases have
  automated coverage but remain unverified live. These are remaining verification
  limits, not reported implementation failures.
- The installed test browser reported an outdated Chromium version. No browser
  update, shared-service change, commit, push, or deployment was performed.

## Implementation sequence and delegation boundaries

The lead owns contracts, interface decisions, integration, and scope changes.
The following are implementation slices, not permission to delegate unresolved
design choices. Supply each handoff with applicable contracts and focused tests.

Contract alignment for this change is complete in the accepted specification and
architecture documents linked above. The remaining execution sequence is:

1. **Minimal token compatibility (complete).** Remove obsolete frontend
   `repo`-scope requirements and the scope-specific reconnect path; replace
   their tests with GitHub App empty/omitted-scope cases while preserving
   response validation. See [progress](#progress).
2. **OAuth sign-in checkpoint.** Use the existing local debug setup for
   protected OAuth sign-in and `/user` verification only. Do not perform
   repository discovery before the API/controller slice. No repository writes
   happen in this checkpoint. If protocol assumptions fail, stop and report
   evidence; do not add callback exceptions, mediator routes, or tooling
   workarounds.
3. **API/controller slice.** Implement the values and interfaces above,
   authorization cleanup, paginated discovery, stale-result handling, access
   checks, and empty-repository errors in `github_api.dart`,
   `github_controller.dart`, and their tests plus `github_transfer_test.dart`.
   Replace obsolete scope fixtures and tests; do not retain them as a second
   authentication mode. Keep paginated request helpers private and report exact
   public signatures and checks before UI integration. No mediator runtime,
   session, schema, route, or dependency changes are planned. Verify its
   existing OAuth and token tests instead of creating a second implementation
   slice; add a test only for a demonstrated coverage gap.
4. **UI/composition slice.** After API/controller interfaces pass their focused
   checks, implement the single setup picker, access management, explicit refresh,
   errors, fixed transfer inputs, and public slug wiring in
   `github_panel.dart`, `github_workspace_panel.dart`, `github_browser.dart`,
   necessary app/workspace plumbing, `Makefile`, and matching tests. Do not edit
   API/controller files without a lead-coordinated handoff.
5. **Live discovery protocol gate.** Verify discovery through the integrated
   production UI before attempting transfer writes. The new required API
   signatures and their UI callers must compile together; do not add temporary
   probe code or compatibility wrappers merely to test discovery earlier. Verify accessible
   installations, repository discovery, and empty-repository responses, reporting
   unavailable live cases as limitations. Do not write to repositories in this
   gate. A contrary result requires lead assessment and approval before changing
   the design.
6. **Integration and checks.** The lead inspects the complete combined diff and
   callers. Run focused tests, analysis, web build, mediator tests, and the live
   browser pass below. Update the tracked setup playbook and this checklist.
7. **Independent review.** Once implementation and initial checks finish, capture
   the complete task-only scope, including additions, deletions, renames, and
   relevant non-ignored untracked files. Give the same diff, contracts,
   constraints, and check evidence to one fresh correctness reviewer and one
   fresh reduced-principles reviewer in parallel, read-only. Wait for both
   outcomes; failed reviews remain incomplete. Verify findings, fix concrete
   defects in the responsible slice, record rejected/deferred findings with
   reasons, and use focused checks rather than a review loop.

For every implementation handoff:

- **Decided by lead:** ownership, interfaces, token type, navigation flow,
  persistence policy, publication safety, empty-repository behavior, and stated
  acceptance criteria in this plan.
- **Worker discretion:** local helper names, small parsing details, widget layout
  within existing components, test organization, and error wording beyond the
  fixed README message.
- **Escalate:** ownership/interface changes, dependencies, persistence formats,
  mediator runtime changes, unplanned platform/bootstrap work, weaker
  validation, partial-list selection, cross-component behavior changes, and
  any failed protocol assumption. Do not implement speculative fallbacks.

Do not run writers concurrently on the same files or build outputs. Separate
API and UI slices are sequential because both depend on controller interfaces.
There is no planned mediator implementation slice. No worktree is needed unless later
execution requires overlapping writes or isolated build state.

## Verification and acceptance

- [ ] OAuth works with GitHub App credentials, PKCE, and empty/omitted scope;
  malformed responses and unsafe navigation still fail. Refresh tokens and
  secrets never reach frontend storage, logs, screenshots, or tracked files.
- [ ] Multiple personal/organization installations and multiple repository pages
  produce one sorted, deduplicated authorized list. Partial failures, malformed
  pages, deadline expiry, and rate limits show retry, not a selectable partial
  result. No arbitrary pagination URL receives credentials.
- [ ] Saved choices are account-scoped and require current membership. Logout,
  account switching, stale async results, deleted/replaced repositories, renamed
  repositories, and changed branches cannot redirect a transfer silently.
- [ ] Setup picker search only filters results. Setup confirmation saves the
  exact selected repository; cancellation/save failure leaves the old choice.
  Import and Commit display/use the saved selection without another picker or
  selection save. Read-only repositories allow import but
  not commit. Archived/disabled repositories cannot receive commits.
- [ ] Empty repositories show the README message with no blob uploads, branch
  creation, or commits. Generic missing/forbidden/conflicting responses are not
  mislabeled empty. After adding a README externally and refreshing, transfers
  work. A repository with a real empty-tree commit is not mistaken for a
  repository with no commits.
- [ ] Managing access opens the right validated GitHub page. Adding/removing
  access and explicit refresh update choices. No installations, organization
  approval requirements, or suspended/unavailable access have actionable states
  without pretending to know an approval status GitHub has not returned.
- [ ] Commits preserve structural validation, unrelated files, one commit and
  force-disabled publication. No automatic write retries, force pushes,
  repository initialization, or fallback to another repository. Permission and
  protected-branch errors do not clear an otherwise valid login.
- [ ] Imports preserve additive merge/collision behavior and never trigger a
  commit. Local canvas capture, transfer interlock, logout retry, response/byte
  limits, and sanitized errors remain covered by existing tests.
- [x] Run focused Chrome tests under `test/github/` and
  `test/app/github_workspace_test.dart`, then `flutter analyze` and
  `flutter build web` with both configured public defines. Run the full Chrome
  suite once before any feature commit:
  `CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome`.
- [x] Run `go test ./...` in the mediator repository; run `go test -race ./...`
  if session/concurrency code is touched under a separately approved change.
- [ ] Delegate one live browser pass through the existing `elseplane-debug`
  workflow. Test sign-in, reload before first selection, two authorized
  repositories, selection cancellation, management/refresh, one nonempty-repo
  import and commit using the displayed selection without a second picker, and
  empty-repository rejection. Use designated test
  repositories for intentional writes; never repurpose unrelated user data.
  Report unavailable organization or permission scenarios as limitations rather
  than pretending fake-provider coverage is a live verification.
- [x] Complete both independent reviews; record fixes and any rejected/deferred
  findings, or explicitly record none. Inspect final diffs/status in both
  repositories and documentation links. Do not stage, commit, push, or deploy
  without a separate request.

## Execution inputs and evidence to collect

There are no remaining product-design questions. Execution needs the public
GitHub App slug and identification of repositories safe for intentional test
commits. Read these from non-secret setup evidence where available; ask for
confirmation before using an uncertain repository for writes.

Measure actual GitHub App exchange/discovery behavior, browser cross-origin
requests, pagination headers, default-branch/empty-repository responses, and
live access changes during the protocol/browser gates. These are verification
inputs, not deferred architectural decisions. A contrary result requires lead
assessment and approval before changing this design.
