# Creation tools

- Follow [editor lifecycle ownership](../../../../docs/arch/editor-lifecycles.md),
  the [interaction model](../../../../docs/specs/interaction-model.md), and the
  [documentation map](../../../../docs/README.md).
- `CanvasInput` arbitrates pointer ownership and dispatches accepted samples.
  Tools retain local drafts and produce element values or raw pen samples;
  `EditorSession` commits document changes.
- Read creation defaults from the session. Do not add widgets, theme lookup,
  storage, or browser APIs here.
- Persisted element views and previews belong in `../elements/`; shared
  calculations belong in `../../geometry/`. Import reusable geometry directly;
  tools do not re-export it. Creation defaults, including the automatic arrow
  bend, remain tool-owned.
- Keep creation sampling and cancellation tests under
  `test/canvas/editor/tools/`. Element views, editor resources, and options have
  their suites under `test/canvas/editor/elements/`; mixed selection and
  navigation belong to editor input tests.
