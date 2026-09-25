# Annotation module

This folder contains the native markup workflow:

- `MarkupEditorView.swift` — tool palette, drawing canvas, selection, direct handles, selected-object inspector, and non-destructive save flow.
- `MarkupRenderer.swift` — flattening of the final annotations into a new PNG at source-image resolution.

The original capture is immutable. Saving inserts the flattened annotated copy into ClipMonster 2.0 history and the system clipboard. After save, the Direct edition can auto-paste that copy; the Store edition leaves it on the clipboard.

The editor receives a full decoded `NSImage` for the duration of the sheet only. History itself stores the PNG on disk and a 128px thumbnail in RAM. Annotated copies follow the same persistence, Finder, Preview, drag, OCR, and copy-path paths as any other image item.
