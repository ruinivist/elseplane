# Creation tools

- CanvasInput arbitrates pointer ownership and dispatches accepted samples to tools.
- Tools retain local drafts and produce element values or raw pen samples. EditorSession commits document changes.
- Read creation defaults from the session. Do not add widgets, theme lookup, storage, or browser APIs here.
- Use ordinary imports. Persisted element views and preview painters belong in ../elements/; shared calculations belong in ../../geometry/.
