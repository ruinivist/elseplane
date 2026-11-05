# Project guidance

- Elseplane is an infinite-canvas app in active development; backward
  compatibility is not required yet.
- Required before changing the project: read [the documentation map](docs/README.md)
  and relevant local `AGENTS.md`. Before structural changes, read
  [ownership and allowed dependencies](docs/arch/ownership.md); before behavior
  changes, read the accepted [interaction model](docs/specs/interaction-model.md).
  These contracts are mandatory, not optional background reading. Use the
  [architecture overview](docs/arch/README.md) for system context and read other
  architecture documents when the task touches their responsibilities. Plans,
  research, and archived notes do not override the accepted contracts.
- Prefer coherent root-cause changes over local patches. Validate input at
  trust boundaries and preserve error handling that prevents data loss.
- We own `infinite_lazy_grid`; suggest changes there when its behavior belongs
  to that library. We maintain a `flutter_markdown_plus` fork: use its exposed
  styling API first, and suggest a fork change when rendering mechanics require
  it.
- Use dependencies available across Flutter platforms. At this stage, build
  and verify web only.
- Test behavior and failure boundaries, not theme-token values. Run focused
  browser tests with
  `CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome <test-file>`.
  For code changes, use `flutter analyze` and `flutter build web`; run the full
  Chrome suite once before committing feature or fix work. Styling/refactor
  changes can skip tests; documentation-only changes need link and diff checks.
- Use lowercase Conventional Commit subjects (`type: description`), 4–6 words
  total.
