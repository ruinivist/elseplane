---
name: elseplane-debug
description: Debug and test Elseplane with one owned Flutter run and its incognito Chrome browser.
---

# Elseplane debugging and browser testing

This self-contained workflow starts one owned Flutter debug run and attaches
`agent-browser` to its incognito Chromium. Run commands from the repository root.

## Quick start

| Command | Effect |
| --- | --- |
| `make debug-start TASK=shape-resize-1` | Start the owned Flutter/Chrome run; wait for VM-service and CDP readiness. |
| `make debug-status TASK=shape-resize-1` | Read-only owner and runner status; it does not inspect UI or auth. |
| `make debug-reload TASK=shape-resize-1` | Request hot reload; `state: requested` is not completion. |
| `make debug-restart TASK=shape-resize-1` | Request hot restart; `state: requested` is not completion. |
| `make debug-stop TASK=shape-resize-1` | Stop the owned run safely, after debugging is finished. |

Use a fresh unique lowercase task slug of at most 48 characters, and the same
`TASK` for every command in that run. A stopped task directory is never reused.

Run `make debug-start TASK=shape-resize-1`. On success, stdout contains one JSON
object. Copy its literal lowercase `browser_session` value; never derive or
guess session, tmux, or run-directory names. `state: ready` means only that the
VM-service URI file and CDP page are present; it does not mean the app UI or
authentication is ready. If a command fails, stderr starts with a JSON error
object (`error_code`, safe `message`, and `next_action`), followed by Make's
error banner and a nonzero exit. Parse the first JSON line, not all of stderr.

Then [attach to the existing app tab](#attach-to-the-running-app), optionally
follow the [authentication checkpoint](#optional-authentication-checkpoint),
and debug the task-specific UI. Use reload or restart only as needed. Run
`make debug-stop TASK=shape-resize-1` only when finished; do not include it in
the startup commands.

`debug-status` can report `starting`, `ready`, or `stopped`; `starting` means
readiness has not passed. Authentication is not managed (`auth` is
`not_restored` on start and `not_managed` otherwise). Stop reports
`state: stopped` and `browser_disconnect: closed`, `absent`, or `manual`.

For focused Flutter output, use the returned `log_path`; keep the log private,
as it may contain the authenticated VM-service URI. If stop reports
`browser_disconnect: manual`, follow its `warnings` and `next_action`. If that
action asks you to close the browser, first list sessions with
`agent-browser session list --json`; close only the exact returned
`browser_session` if it is still listed. Do not run `close` for an absent
session, as that can create its daemon.

## Prerequisites and ownership

Read [`local-mediator/README.md`](../../../local-mediator/README.md) for the
machine-local setup. This workflow requires native Linux, `python3`, `make`,
`tmux`, Flutter, `/usr/bin/chromium`, `agent-browser`, Go, Docker Engine and
Compose, a trusted localhost certificate, and the configured Caddy and native
Go mediator services already running. Do not install or start shared services
as part of this workflow. The debug Make targets manage only the owned
Flutter/Chrome run. The README covers OAuth configuration; never inspect
credential files.

Each task gets a new Flutter-launched, headless, incognito Chrome process and an
exclusive private directory at
`<repo>/local-mediator/debug/<TASK>`. The directory contains `owner.json`,
`flutter.log`, and `vm-service.uri`; it is ignored local state. Start waits up
to 120 seconds for CDP and the VM service to become ready, not for the app UI.
It fails safely for occupied ports or an existing task directory/session; do
not kill processes, clear caches, or remove prior task artifacts to make room.
Use `debug-status` for read-only ownership and runner readiness checks. It does
not print the VM URI.

The returned `browser_session` attaches to CDP on loopback port 3004. Use only
the browser and tmux names from this task's JSON, never another task, a personal
browser, or the user's tmux session `0`. There can be only one owned Flutter
debug run on ports 3000 and 3004 per workspace.

Before browser bootstrap and each task, check effective environment and
`agent-browser` config defaults for state, profile, restore, legacy session
name, auto-connect, and CDP. Do not dump environment or config contents or
print their values. Clear conflicting environment overrides on each CLI call
using the exact variable names documented by the installed CLI. If a conflicting
config default cannot safely be overridden, stop and ask the machine owner. Do
not edit global config or connect to a personal browser.

## Attach to the running app

After `debug-start` reports readiness, substitute its literal lowercase
`browser_session` value into each command below. Connect to CDP, select the
existing app tab by its listed ID, and verify the app URL and stable CDP
`targetId`. Do not create a tab or use `--pin-tab`.

```sh
agent-browser --session '<browser_session>' connect 3004
agent-browser --session '<browser_session>' tab list --json
agent-browser --session '<browser_session>' tab PASTE_LISTED_TAB_ID
agent-browser --session '<browser_session>' get url
```

The selected tab must be `https://localhost:3002`. For authenticated work,
follow the optional checkpoint steps below, then open the completion URL in
this same selected tab. Re-list tabs to confirm the target ID did not change.
The completion marker invokes the app's normal mediator account check; it does
not bypass authentication or make an expired cookie valid.

Wait for the task-specific UI you need, not generic network idle. Use fresh
accessibility snapshots after navigation or UI changes, then act on their refs;
use screenshots for canvas layout:

```sh
agent-browser --session '<browser_session>' snapshot -i
agent-browser --session '<browser_session>' click @eN
agent-browser --session '<browser_session>' fill @eN "text"
agent-browser --session '<browser_session>' press Enter
agent-browser --session '<browser_session>' wait --fn "<task-specific UI condition>"
agent-browser --session '<browser_session>' screenshot
agent-browser --session '<browser_session>' console
agent-browser --session '<browser_session>' errors
```

Replace `<browser_session>` and the listed-tab placeholder with their literal
values. If Flutter controls are missing, snapshot, focus the `Enable
accessibility` ref, press Enter, wait briefly, and snapshot again. Do not read
app state through arbitrary DOM or page-script evaluation. Console and page
errors may contain secrets: inspect only in the private task context and redact
before sharing. Never inspect token endpoints, authorization headers, or token
request/response bodies.

## Optional authentication checkpoint

For an authenticated task only, load the cookie-only checkpoint
`local-mediator/browser/auth-state.json` if it exists and is valid. Do not load
it for unauthenticated work or logout tests. With the app tab selected, load it
and open the completion URL in that same tab:

```sh
agent-browser --session '<browser_session>' state load local-mediator/browser/auth-state.json
agent-browser --session '<browser_session>' open 'https://localhost:3002/?github=complete'
agent-browser --session '<browser_session>' tab list --json
agent-browser --session '<browser_session>' snapshot -i
```

Verify the expected account in the app UI and the same CDP target ID. Never
inspect cookies, token values, storage bodies, or OAuth requests. The checkpoint
contains no page storage or workspace state; mediator and backend state remain
shared. Do not save task mutations over the checkpoint. If the checkpoint is
missing, expired, or logged out, stop and ask the machine owner for a new
human-confirmed sign-in.

If the authenticated task has no saved GitHub destination, a browser reload or
Flutter hot restart may show Connect GitHub despite a valid cookie. Open the
completion URL again in the same tab to rerun the account check, then verify the
account and target ID. This reruns the check; it is not authentication refresh
or recovery from logout. Do not reload the baseline browser state or reapply
the checkpoint.

Treat the checkpoint as immutable during debugging. Only a human-confirmed,
dedicated headed bootstrap may replace it; never use a personal browser. Keep
all files private (`umask 077`), verify the expected account in the app UI, and
wait for explicit human confirmation before saving. Run the bootstrap setup in
one shell:

```sh
umask 077
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
AUTH_DIR="$ROOT/local-mediator/browser"
TASK_ID="$(date +%Y%m%d%H%M%S)-$$-auth-bootstrap"
BOOTSTRAP_SESSION="auth-bootstrap-$TASK_ID"
CHECKPOINT="$AUTH_DIR/auth-state.json"
STAGED="$AUTH_DIR/auth-state.json.tmp.$TASK_ID"
mkdir -p "$AUTH_DIR"
chmod 700 "$AUTH_DIR"
printf 'ROOT=%s\nBOOTSTRAP_SESSION=%s\nSTAGED=%s\nCHECKPOINT=%s\n' \
  "$ROOT" "$BOOTSTRAP_SESSION" "$STAGED" "$CHECKPOINT"
agent-browser --session "$BOOTSTRAP_SESSION" --headed --args "--incognito" open https://localhost:3002
```

The setup and save happen in separate tool calls, so shell variables do not
persist. Record the printed values and substitute their literal, shell-quoted
values below after the human confirms the account. Save only to the staged path,
sanitize, publish atomically, and close only the owned bootstrap session:

```sh
ROOT='<recorded ROOT>'
BOOTSTRAP_SESSION='<recorded BOOTSTRAP_SESSION>'
STAGED='<recorded STAGED>'
CHECKPOINT='<recorded CHECKPOINT>'
agent-browser --session "$BOOTSTRAP_SESSION" state save "$STAGED" &&
  python3 "$ROOT/.agents/skills/elseplane-debug/scripts/clean-auth-state.py" "$STAGED" &&
  mv -f -- "$STAGED" "$CHECKPOINT" &&
  agent-browser --session "$BOOTSTRAP_SESSION" close
```

If save, cleanup, or rename fails, stop and keep the staged file private; do not
use a partial file or replace the known checkpoint. For a legacy unsanitized
checkpoint only, get explicit machine-owner approval, then run the cleaner once
on that checkpoint. Do not run it on an already-normalized checkpoint. The
cleaner keeps only the existing `__Host-oauth_bridge` cookie, empties origins,
and fails without publishing a missing, malformed, or ambiguous cookie. Never
display, copy, log, or commit checkpoint contents.

## Reload, restart, and stop

Within one task, the incognito browser and its task-local storage persist across
reloads and Flutter hot reload/restart; a new task starts a new browser context.
Use the Make targets, which address only the verified owner run:

```sh
make debug-reload TASK=shape-resize-1
make debug-restart TASK=shape-resize-1
```

Flutter web debugging uses the DWDS web subset, not the full native Dart debug
surface. The private `vm-service.uri` file contains a plain authenticated
WebSocket URI, including its auth code; the raw pane log may contain it too.
Never print, paste, or share either. Use Flutter/DevTools for debugging; if
isolate-level diagnosis requires a probe, keep the URI in-process and use only a
bounded Node built-in WebSocket JSON-RPC probe. Do not install a client library
or add a helper client.

`make debug-stop TASK=shape-resize-1` disconnects only an active attached
`agent-browser` session after verifying its owner, asks Flutter to quit, and
waits up to 30 seconds. If Flutter does not exit, the command fails and leaves
the run intact; do not force-kill it. It never stops Go, Caddy, another tmux
session, or the user's session `0`. Closing the owned Chrome ends its incognito
task-local storage. Do not use `close all` or clear caches.

## Authorized debugging repository

`ruinivist/elseplane-notes` is the owner's designated private debugging
sandbox. Verify the selected repository is exactly that repository before
writing; its contents may be imported, committed, overwritten, or deleted for
debugging. This permission does not extend to other repositories or
account-wide actions, including access revocation. Authorize remote writes only
when the task calls for them.
