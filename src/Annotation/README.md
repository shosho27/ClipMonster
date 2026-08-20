# Annotation module

This folder contains the native markup workflow:

- `MarkupEditorView.swift` — tool palette, drawing canvas, selection, direct handles, selected-object inspector, and non-destructive save flow.
- `MarkupRenderer.swift` — flattening of the final annotations into a new PNG at source-image resolution.

The original capture is immutable. Saving inserts the flattened annotated copy into ClipMonster 2.0 history and the system clipboard.
