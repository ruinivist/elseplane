# Element presentation

- Views receive immutable element values and session-derived interaction flags. Request saved changes through EditorSession operations.
- CanvasView retains resources by ID and type outside lazily culled widgets. Text, code, media, and pen have resource owners; shapes and arrows render directly from values.
- Inline Markdown attachment and HTTPS image loads belong to retained text resources. Load lazily, retain surviving sources across culling and restoration, and keep storage reads out of preview widgets.
- Removal invalidates resources immediately. Dispose controllers and focus nodes only after their consumers detach.
- Keep clipboard and device-image edit workflows with their editor. Resource owners retain controllers, drafts, image display loads, and geometry caches.
- Use ordinary imports and keep component geometry local. Put shared canvas controls in ../widgets/ and app-wide Flutter primitives in lib/ui/common/.
