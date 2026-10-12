# elseplane

https://elseplane.ruiny.de/

Infinite canvas with first-class support for code and Markdown.

## Why?

Code and markdown are not at all supported in excalidraw.
Tldraw default doesn't as well, you can extend it via their SDK but the license
is too restrictive.

## Features

- code and markdown support
- a little bit nice ui
- more intuitive controls ( hopefully )
- less bloat ( focus is on keeping the ui out of the way )
- flutter so would be 100% cross platform ( need to test still )
- self host with sharing ( planned )

## Feature flags

Edit the `static const` values in `lib/feature_flags.dart` and rebuild the app.
`themeSelection` and `surfaceStyleSelection` default to `false`: the app uses
Dark and Glass, and hides their settings. Enable either flag to restore its
selector. New users start in Dark and Glass even when selection is enabled.

Flags belong at the feature's entry points and controls. Future tool flags
must guard activation and keyboard shortcuts as well as toolbar buttons.

## TODO

a vague list

- self host docker image
- more comprehensive file switching support
- LSP integration
- better media player support for videos etc
- perf issues on draw
