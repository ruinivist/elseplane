# Development

## Prerequisites

Install Flutter with a Dart SDK satisfying the constraint in `pubspec.yaml`,
then fetch project dependencies:

```sh
flutter pub get
```

The Makefile's browser run targets require Chrome. `make deploy` additionally
requires Wrangler configuration and credentials.

## Commands

| Command | Effect |
| --- | --- |
| `make run` | Run the app in Chrome with the current Git SHA. |
| `make run-release` | Run a release build in Chrome with the current Git SHA. |
| `make build` | Build the web app with the current Git SHA. |
| `make deploy` | Build, then run `wrangler deploy`. |
| `make fmt` | Format Dart files under `lib/`, excluding generated files. |
| `make preview` | Start Flutter's widget preview tool. |

Direct checks used for web development:

```sh
flutter analyze
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome <test-file>
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
