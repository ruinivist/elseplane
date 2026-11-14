---
name: elseplane-browser
description: Use when testing or debugging the local Elseplane app with agent-browser, especially authenticated flows that need an auth checkpoint and isolated browser sessions.
---

# Elseplane browser testing

Use this skill with the general `agent-browser` skill. It covers Elseplane's
local services and safe session handling; the general skill covers browser
commands and interaction details.

## Before using the CLI

Load the general `agent-browser` skill, then read the installed CLI guide with
`agent-browser skills get core`. Read its command, authentication, and session
references as needed. Use those installed references for exact CLI syntax.

Run commands from the repository root with
`cd "$(git rev-parse --show-toplevel)"`. Check that `agent-browser` is
available and whether the needed local services are already running. Do not
start duplicate servers or stop processes you do not own. This workflow does
not start or stop services automatically.

Before launching any session, including bootstrap, check effective environment
and agent-browser config defaults for state, profile, restore, legacy session
name, and auto-connect/CDP. Do not dump environment or config contents or print
values. Clear conflicting environment overrides for each CLI call (for example,
with `env -u` for the specific variables documented by the installed CLI); shell
changes do not persist between tool calls. If a conflicting config default
cannot be safely overridden for this workflow, stop and ask the machine owner.
Do not edit global config or connect to a personal browser.

For machine-local prerequisites and setup, follow
[`local-mediator/README.md`](../../../local-mediator/README.md). That file is
inside an ignored directory and may be absent on a fresh checkout. If it is
absent, ask the machine owner to provision local certificates and OAuth setup
before testing sign-in; do not inspect credential files. Development commands
are in [`docs/playbooks/development.md`](../../../docs/playbooks/development.md).

The local UI is `https://localhost:3002`; the mediator is
`https://localhost:3003`. Flutter serves HTTP on `127.0.0.1:3000` and the Go
mediator listens on `127.0.0.1:3001`; Caddy proxies them on HTTPS and runs in
Docker. From the repository root, the local setup uses
`make -C local-mediator up`, then `make -C local-mediator mediator`, and either
`make run` or `make run-release`. Do not run both Flutter targets at once. In
release mode, open `https://localhost:3002` manually; the Flutter SDK ignores
the HTTPS launch URL in that mode.

## Choose an authentication path

- For unauthenticated work, open the UI in a fresh, uniquely named headless
  session. Do not pass `--state`, `--profile`, or `--restore`.
- For authenticated work, use the valid saved checkpoint at
  `$ROOT/local-mediator/browser/auth-state.json` with `--state` on the first
  open only. If it is missing or expired, stop and ask a human to sign in using
  the bootstrap flow below. Do not try automatic refresh or reauthentication.
- For logout tests, do not restore or refresh authentication during the test.
  Do not sign out merely to check whether a checkpoint is valid.

Never use a personally attached browser. A human can sign in in a dedicated,
headed bootstrap session. Ask them to keep its window open and wait for their
explicit confirmation before continuing. Verify the expected local app account
in the UI, not through cookie, token, or OAuth API inspection. Save the
checkpoint before closing that session, then use it only to start a separate
headless task session.

## Create or refresh a checkpoint

Only a human-confirmed bootstrap session may replace the checkpoint. Keep the
directory private, save to a unique temporary file, then rename it over the
checkpoint on the same filesystem. The rename prevents other tasks from reading
a partially written checkpoint. Run the setup in one shell; if using separate
CLI calls, substitute the exact printed session and path values because shell
variables do not carry between calls.

```sh
umask 077
ROOT="$(git rev-parse --show-toplevel)"
AUTH_DIR="$ROOT/local-mediator/browser"
TASK_ID="$(date +%Y%m%d%H%M%S)-$$-auth-bootstrap"
BOOTSTRAP_SESSION="auth-bootstrap-$TASK_ID"
CHECKPOINT="$AUTH_DIR/auth-state.json"
STAGED="$AUTH_DIR/auth-state.json.tmp.$TASK_ID"
mkdir -p "$AUTH_DIR"
chmod 700 "$AUTH_DIR"
printf 'Session: %s\nStaged file: %s\nCheckpoint: %s\n' \
  "$BOOTSTRAP_SESSION" "$STAGED" "$CHECKPOINT"
```

Open the local UI in the dedicated headed session. Pause for the human to sign
in and confirm, then verify the expected account in the app UI.

```sh
agent-browser --session "$BOOTSTRAP_SESSION" --headed open https://localhost:3002
```

After confirmation, save and publish the checkpoint before closing the
bootstrap session:

```sh
agent-browser --session "$BOOTSTRAP_SESSION" state save "$STAGED" &&
  chmod 600 "$STAGED" &&
  mv -f -- "$STAGED" "$CHECKPOINT"
```

Only after that succeeds, close that owned session:

```sh
agent-browser --session "$BOOTSTRAP_SESSION" close
```

If save or publication fails, stop. Do not use a partial file or replace the
known checkpoint with state from a failed or mutated task. Keep any temporary
file private and handle cleanup without displaying its contents.

## Use isolated task sessions

Give every task and parallel worker a different session name. A name returned
by `session id --scope worktree` is not unique for parallel work in the same
worktree; add a task-unique suffix, such as a timestamp, shell process ID, and
task ID. Record the generated literal and pass that same `--session` value to
every command for the task. Do not rely on a default session or on shell
variables persisting across separate tool calls.

Start an authenticated task with the shared checkpoint only on its initial
open:

```sh
TASK_ID="$(date +%Y%m%d%H%M%S)-$$-canvas-check"
TASK_SESSION="elseplane-$TASK_ID"
ROOT="$(git rev-parse --show-toplevel)"
agent-browser --headed false --session "$TASK_SESSION" \
  --state "$ROOT/local-mediator/browser/auth-state.json" \
  open https://localhost:3002
```

For anonymous work, use a new task session and omit all state/profile/restore
options:

```sh
TASK_ID="$(date +%Y%m%d%H%M%S)-$$-canvas-check"
TASK_SESSION="elseplane-$TASK_ID"
agent-browser --headed false --session "$TASK_SESSION" open https://localhost:3002
```

Pass the same explicit `--session` value to each later command. Do not pass
`--state` again, save task mutations to the shared checkpoint, share a restore
key or profile, close all sessions, or clear another worker's cookies or
storage. Close only the session you own when finished; the task session's
browser changes are disposable.

## Inspect the app safely

For authenticated tasks, verify the expected account in the app UI after opening
and check the selected repository before remote actions.

Wait for the expected app UI to be ready rather than waiting indefinitely for a
generic network-idle condition. Use `snapshot -i` and its current element refs
for controls; use screenshots to diagnose canvas layout. Enable
Flutter accessibility when controls are missing from the accessibility view.
Snapshots and screenshots are not token exports, but page and network output can
still contain secrets. Do not inspect `/oauth/*/token`, authorization headers, or
token request/response bodies, and do not print or copy browser state.

## Limits and shared effects

An exported auth checkpoint is sensitive: it can include GitHub cookies as well
as local app state. Keep it only at the ignored path above. Never display, log,
commit, copy into shared artifacts, or save worker mutations back to it. Treat
it as a best-effort auth checkpoint, not an IndexedDB or full workspace restore.

Browser sessions are separate, but the mediator and GitHub account are shared.
Logout, expiry, refresh, or revocation in one session may invalidate the
checkpoint or other sessions. Repository changes are shared too. This workflow
does not isolate backend state or remote writes. Local OAuth setup may grant
broad repository access. Authorize GitHub writes or revocations only when the
task calls for them; prefer a disposable repository and warn before changing
live data. If authentication disappears unexpectedly, stop authenticated
actions and ask a human to refresh the checkpoint. Never overwrite it from the
failed session.
