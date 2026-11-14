# Development

## Browser-debug quick start

Run commands from the repository root with one fresh, unique lowercase task
slug of at most 48 characters. Reuse that `TASK` for the run's commands.

| Command | Effect |
| --- | --- |
| `make debug-start TASK=shape-resize-1` | Start one owned incognito Flutter/Chrome debug run. |
| `make debug-status TASK=shape-resize-1` | Read-only ownership and runner-readiness check. |
| `make debug-reload TASK=shape-resize-1` | Request hot reload for that run. |
| `make debug-restart TASK=shape-resize-1` | Request hot restart for that run. |
| `make debug-stop TASK=shape-resize-1` | Safely stop that run after debugging is finished. |

Start the run, copy the literal lowercase `browser_session` from its successful
JSON output, then [attach CDP to the existing app tab](../../.agents/skills/elseplane-debug/SKILL.md#attach-to-the-running-app).
For authenticated work only, follow the skill's [optional authentication
checkpoint](../../.agents/skills/elseplane-debug/SKILL.md#optional-authentication-checkpoint).
Debug the task UI, using reload or restart only as needed; run
`make debug-stop TASK=shape-resize-1` only when finished. `state: ready` means
runner readiness, not app UI or authentication readiness. On failure, parse the
first JSON error line on stderr (`error_code`, `message`, `next_action`), not
Make's following error banner. See the [self-contained debug
skill](../../.agents/skills/elseplane-debug/SKILL.md) for the complete workflow
and safety details.

## Prerequisites

Install Flutter with a Dart SDK satisfying the constraint in `pubspec.yaml`,
then fetch project dependencies:

```sh
flutter pub get
```

The Makefile's browser run targets require Chrome. `make deploy` additionally
requires Wrangler configuration and credentials.

The owned browser-debug targets require native Linux, `python3`, `make`, `tmux`,
Flutter, `/usr/bin/chromium`, `agent-browser`, Go, Docker Engine and Compose,
and trusted local HTTPS. Caddy and the configured native Go mediator must
already be running. These targets do not install or start shared services; they
manage only the owned Flutter/Chrome run and attached browser session. See
[`local-mediator/README.md`](../../local-mediator/README.md) for setup.

These are separate targets; the defaults for `make run`, `make run-release`,
and `make build` remain unchanged.

## Commands

| Command | Effect |
| --- | --- |
| `make run` | Run the app in Chrome with the current Git SHA. |
| `make run-release` | Run a release build in Chrome with the current Git SHA. |
| `make build` | Build the web app with the current Git SHA. |
| `make deploy` | Build, then run `wrangler deploy`. |
| `make fmt` | Format Dart files under `lib/`, excluding generated files. |
| `make preview` | Start Flutter's widget preview tool. |

The five `make debug-*` commands are listed in the quick start above.

Direct checks used for web development:

```sh
flutter analyze
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome '<test-file>'
flutter build web
```

Test behavior and failure boundaries rather than theme-token values. Run focused
tests while changing code; run the full Chrome suite once before committing a
feature or fix. Documentation-only changes need link and diff checks, not a
Flutter test or build.

## Feature flags

Edit the `static const` values in `lib/app/feature_flags.dart` and rebuild.
`themeSelection` and `surfaceStyleSelection` default to `false`: the app uses
Dark and Glass and hides their settings. New users start in Dark and Glass even
when selection is enabled.

App composition owns these flags and supplies appearance callbacks to Settings.
Settings shows only controls for callbacks it receives. Future tool flags must
guard activation and keyboard shortcuts as well as toolbar buttons.
