# Project Guidance

- This is an infinite canvas project under active development.
- Before structural changes, read [the architectural constitution](docs/ARCHITECTURE.md) for ownership and allowed dependencies; follow [the refactor roadmap](docs/REFACTOR_PLAN.md) when migrating existing code. The architecture defines implemented ownership and allowed dependencies; the roadmap records the migration.
- The [interaction model](docs/Interaction%20model.md) governs product behavior. Older notes do not override it or the architectural constitution.
- Backward compatibility is not required yet.
- Prefer globally coherent, root-cause changes over local patches, even when they require breaking changes.
- We own `infinite_lazy_grid`. When a change is better suited to that library, suggest making it there.
- We maintain our own fork of `flutter_markdown_plus`. Use the library's exposed styling options as intended first; if they cannot achieve the required styling, suggest modifying the fork.
- Use packages that are available on all platforms but only test build for "web", no need to test for any others at this stage.
- Nested folders can have their own AGENTS.md, read those if you are working in a relevant directory.

# UI Decisions

- Use `scroll_animator` `0.3.0` with `ChromiumEaseInOut` for smooth pointer scrolling
- Put app-wide Flutter primitives in `lib/ui/common/` and read semantic `BTheme` values internally.
- Keep canvas-specific widgets in `lib/canvas/editor/widgets/`.
- Do not expose visual overrides until a concrete product requirement justifies an explicit semantic API.
- Keep concrete Starless Light palette, typography, syntax theme, and reusable geometry in the app theme; keep component-specific geometry local to each componen. Example: instead of hardcoding random number sizes that we are using repeatedly across the app as a "preferred size" make it owned
  by the app. Example something like an icon should be consistent unless component-specific override is needed, so an icons size belongs some place
  in theme but a widget specific larger icon size can be hardcoded inline.
- Before changing widget behavior or interactions, read and follow the app-wide [interaction model](docs/Interaction%20model.md).

# Testing guidance

- Run browser-dependent tests with `flutter test --platform chrome <test-file>` (Chromium: prefix `CHROME_EXECUTABLE=/usr/bin/chromium`).
- Only test for "behavior" and not UI token values as such token values can change anytime; behavior like so and so tokens should exist is correct but matchin them against a constant is wrong.
- Keep testing lighter, we'll add tests once we have something concrete but NOT at this stage.
- Don't run the FULL test suite for every change, just ONCE before we commit if we added new features/fixes. For styling/refactors, you can skip tests.
