# Local GitHub App setup

Use this playbook for local web development only. It describes the public app
settings and frontend configuration; client secrets, refresh tokens, certificates,
and mediator state stay in local ignored configuration.

## Prerequisites

- Local trusted HTTPS and the existing GitHub token mediator are configured and
  available.
- The GitHub App is owned by a personal account and can be installed on personal
  and organization accounts.
- See the accepted [interaction model](../specs/interaction-model.md),
  [transfer contract](../specs/folder-based-canvas-transfers.md), and the
  [active implementation plan](../plans/github-repository-selection.md) for
  behavior and outstanding verification.

## Steps

1. Configure the GitHub App with Contents read/write and Metadata read-only;
   grant no other account or organization permissions. Enable expiring user
   access tokens. Disable device flow and automatic user authorization during
   installation, leave the setup URL blank, and keep webhooks inactive.
2. Configure the existing mediator's `github` provider with the app credentials,
   the callback `https://localhost:3003/oauth/github/callback`, and an empty
   scope list (`scopes: []`). Keep the frontend origin at
   `https://localhost:3002` and completion URI at
   `https://localhost:3002/?github=complete`. The existing OAuth flow remains
   responsible for authorization; no `repo`-scope gate is needed. Keep the
   client secret and refresh token in the mediator only.
3. Configure the frontend's public build values together:

   ```text
   GITHUB_MEDIATOR_URL=https://localhost:3003
   GITHUB_APP_SLUG=<public-app-slug>
   ```

   Get the slug from the app's public GitHub URL, such as
   `https://github.com/apps/example-app`. The example slug is generic; do not
   guess a slug or put credentials in build values. Once public slug wiring is
   in place, use the project's Makefile run/build targets to pass these values.
4. With the local proxy running, start the mediator from the repository root
   in a separate terminal and leave it running:

   ```sh
   make -C local-mediator mediator
   ```

   Start the app with both public values configured and connect through the
   GitHub panel. The installation flow
   grants the app access to selected repositories or all repositories; the
   searchable setup picker then chooses one saved destination for both Import
   and Commit. Import and Commit use the displayed saved destination and do not
   reopen the picker.
5. To add or remove repository access, use **Manage repository access** in the
   panel and then select **Refresh** in Elseplane. Choose a repository with a
   default-branch commit. Empty repositories are rejected with: "This repository
   is empty. Add a README on GitHub, then refresh." Add the README on GitHub,
   refresh the list, and select the repository again; Elseplane does not
   initialize repositories.

## Verification and recovery

- Confirm the GitHub panel is configured only when both public frontend values
  are present and the mediator URL uses HTTPS.
- After OAuth, confirm account verification and repository discovery. A failed
  discovery leaves the current saved destination unchanged and can be retried
  with **Refresh**; it does not by itself mean the account is disconnected.
- If the app has no accessible installations or repositories, manage its
  installation grant on GitHub and refresh. Do not replace a missing saved
  choice silently.
- A 401 requires reconnecting. Permission, missing-resource, conflict,
  rate-limit, and uncertain-write errors are distinct; do not diagnose them by
  checking for a `repo` scope or retry a possibly completed write automatically.

Production app hosting, credentials, callbacks, and deployment are outside this
local setup.
