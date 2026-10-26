# Creation tools

- CanvasInput arbitrates pointer ownership and dispatches accepted samples to tools.
- Tools retain local drafts and produce element values or raw pen samples. EditorSession commits document changes.
- Read creation defaults from the session. Do not add widgets, theme lookup, storage, or browser APIs here.
- Use ordinary imports. Persisted element views and preview painters belong in ../elements/; shared calculations belong in ../../geometry/.
- Keep creation sampling and cancellation tests under test/canvas/editor/tools/. Element views, editor resources, and options have their own suites under test/canvas/editor/elements/; mixed selection and navigation belong to editor input tests.
- Import reusable geometry from canvas/geometry/ directly; tools do not re-export it. Creation defaults, including the automatic arrow bend, remain tool-owned.
