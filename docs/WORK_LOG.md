# Work Log: ClipMonster 2.0

## 2026-10-06 — Chrome blank-page click detection

- Actual Chrome hit testing returned `AXScrollArea` for blank webpage space, with the `AXWebArea` underneath it as a child. The ancestor-only page check rejected that valid click.
- Resolve webpage identity through a bounded descendant search on scrolling containers as well as the parent chain. Browser toolbar/tab-strip containers still need a WebArea to qualify. Keep lookups off the UI thread with per-element messaging timeouts.
- Verified the real Chrome blank-page hit resolves the visible viewport. Added an opt-in `--chrome-at-pointer` integration check to the page-target test executable.

## 2026-10-06 — click-to-select capture and cancellation fix

- Removed the screen-covering rectangle selector, which could trap input without a key window. Scrolling Capture now arms a global mouse-up observer; the next ordinary click inside a webpage identifies the browser and its nearest visible scroll area through Accessibility. Toolbars are rejected, document dimensions are clipped to window/screen bounds, and nested scroll areas are preferred.
- Added a small Cancel control while choosing a page, a 60-second idle timeout, and a session-only exclusive Escape hotkey. Cancellation releases controls/event hooks immediately and terminates any running screenshot subprocess. Accessibility lookups run off the main actor with a bounded messaging timeout.
- Validation: build passes; stitching tests pass; viewport/window/display clipping and nested-scroller tests pass; native Escape registration and repeated arm/cancel lifecycle checks pass without changing the clipboard. Full live browser auto-capture still needs user verification.

## 2026-10-06 — scrolling webpage capture

- Added a **Scrolling Capture** button above history search. Select content on one display; scroll the existing browser page with Quartz events and capture overlapping viewports with the macOS screenshot tool.
- Align in pixel coordinates rather than assuming wheel distance or Retina scale. Copy only new bottom strips, compose once, then save through existing disk-backed image history and clipboard handling. Alignment/composition run off the main actor.
- Added Accessibility / Screen Recording checks, a progress panel with Stop & Save / Cancel, global/local Escape handling, focus checks, temporary-file cleanup, pointer restoration, and bounded partial capture messages.
- Validation: `build_app.sh` passes without compiler warnings. Deterministic Swift checks pass at 1× and 2×, including exact full-image pixel equality, the smaller final scroll, unchanged viewports, unrelated images, and invalid dimensions/crops. The isolated native test app showed the expected Accessibility permission notice; full live browser capture remains unverified because that test bundle was not granted permission.

## 2026-09-18 — disk-backed captures (RAM)

- History no longer retains a decoded `NSImage` per screenshot. Each capture is written as `<UUID>.png`; RAM keeps a 128px ImageIO thumbnail plus path/hash/pixel size.
- New `ImageStore` hashes PNG file bytes (no TIFF round-trip), reads pixel size from ImageIO properties, and downsamples on demand: 720px for the in-app overlay, 2048px for Vision OCR, full file for Annotate / copy / Preview / drag.
- Drag copies the stored PNG to a dated temp name instead of re-encoding. Copy puts PNG bytes on the pasteboard.
- Persistence still uses `index.json`; images are always on disk during the session so the list stays small. With **Keep history across reboots** off, those files are removed on quit.
- Live check after rebuild: ClipMonster 2.0 footprint dropped from ~989 MB (666 MB ImageIO) to **39 MB** with the same 50 history items / 34 images.
- `build_app.sh` now links ImageIO, passes Xcode’s Mac SDK + SwiftUI macro plugin path, and exits if `swiftc` fails.

## 2026-08-19 — annotation workflow user-verified

- User exercised the native markup workflow and reported it working after iterative fixes to canvas hit testing, Arrow endpoints, selection, save visibility, text editing, transforms, and direct manipulation handles.
- Current product behavior is documented in `README.md` and `ARCHITECTURE.md`: annotations are non-destructive, save as a new top-of-history clipboard item, and support both direct handles and precise inspector controls.
- The original ClipMonster app remains untouched; all implementation and validation occurred in the independent ClipMonster 2.0 working copy.

## 2026-08-19 — independent 2.0 working copy

- Created from the clean ClipMonster baseline at `../ClipMonster/`; the original was not modified.
- Changed the bundle ID to `com.sashornock.ClipMonster2`, its default persistence folder to `~/Library/Application Support/ClipMonster 2.0/`, and its LaunchAgent label to `com.sashornock.ClipMonster2`.
- Isolated temporary PNG names under `clipmonster2-` so cleanup cannot remove the original app's temporary exports.
- Set non-conflicting initial shortcuts: Control-Option-V opens 2.0, Command-Option-Shift-V pastes its latest image path. Both can be changed within 2.0 Preferences.
- Reserved this copy for the proposed screen-capture markup editor; no markup implementation is included yet.
- Verified the Swift executable and ZIP build. On this macOS 26.6.2 host, the inherited `iconutil` conversion rejects the otherwise correctly sized iconset; the build now reports that as a warning instead of claiming a generated icon. This does not affect the menu-bar SF Symbol.

## 2026-08-19 — architecture refactor before markup

- Split the original monolith into `App/`, `Models/`, `Services/`, and `Views/` without changing the app's behavior.
- `ClipMonster.swift` is now only the SwiftUI application entry point; `AppDelegate` owns menu-bar/popover/hotkey lifecycle, and `ClipboardMonitor` owns capture/history coordination.
- Extracted image OCR, drag temporary-file cleanup, login-item support, persistence value types, and shortcut data into focused files.
- Updated `build_app.sh` to compile nested `src/` folders, which creates a clean `src/Annotation/` seam for the markup editor.
- Rebuilt successfully after the structural move; targeted live smoke checks will follow once annotation controls are introduced.

## 2026-08-19 — native capture markup editor

- Added **Annotate** to the large capture preview.
- Built a dedicated full-size editor with Pen, Arrow, Box, and Text tools, color and stroke-width controls, Undo, and Clear.
- Annotation points are normalized to the displayed capture, then rendered at the source image's original dimensions on save.
- **Save Annotated Copy** creates a new PNG history item via `ClipboardMonitor`; it never alters the original capture. The new item follows the existing persistence, Finder, Preview, drag, OCR, and copy-path workflows.
- Confirmed the full 2.0 bundle builds after the implementation; live interaction smoke testing remains the next check.
- Corrected the 2.0 bundle executable name to `ClipMonster2` (the display bundle remains `ClipMonster 2.0.app`) after a macOS launch check rejected the space-containing executable filename.
- Added the missing `CFBundlePackageType=APPL` bundle metadata required by Launch Services when opening the app bundle.
- Verified that the built `ClipMonster 2.0.app` launches in the macOS GUI outside the sandbox. The interactive editor flow should be smoke-tested from a copied screenshot: preview → Annotate → draw → Save Annotated Copy.

## 2026-08-19 — markup interaction correction

- Replaced the ambiguous segmented text selector with selected-state icon buttons for Pen, Arrow, Box, and Text, including hover labels and accessibility labels.
- Made the entire image overlay a concrete transparent hit target so drawing gestures reliably reach the markup canvas.
- Added tool-specific instruction text directly below the editor canvas.

## 2026-08-19 — annotation save-flow correction

- Saving now places the flattened annotated copy in both ClipMonster 2.0 history and the system clipboard.
- Opening Annotate closes the original preview, and saving returns directly to the history list with the new annotated capture at the top.
- Removed gesture-local start state from Arrow and Box; their endpoints now derive directly from the active drag points, matching the reliable Pen interaction path.

## 2026-08-19 — arrow and selection-tool correction

- Arrow endpoints now come directly from `DragGesture.startLocation` and the current pointer location, eliminating asynchronous view-state dependence.
- Added a Select cursor tool: click an annotation to highlight it, then drag it anywhere on the image. It supports pen strokes, arrows, boxes, and text.

## 2026-08-19 — selected annotation transform inspector

- Added selected-object controls for color, scale (25%–300%), rotation (-180°–180°), and delete.
- The same geometric transforms apply in the SwiftUI editor and in the flattened PNG renderer, so saved copies match the editing preview.

## 2026-08-19 — direct manipulation handles

- Added familiar selection affordances alongside the numeric inspector: dashed bounds, four corner resize handles, and a rotation handle above text, boxes, and pen strokes.
- Arrows use dedicated tail and tip handles, allowing users to reshape their length and direction directly.

## 2026-08-19 — resize-handle identity correction

- Fixed SwiftUI recreating a resize handle whenever its position changed during a drag. Corner handles now have stable identities and remain active throughout scaling.
- Increased the visible resize target to 14×14 points for easier grabbing.

## 2026-08-19 — editable text selection correction

- Selecting a text annotation now focuses an editable text field in the selected-object inspector, so its words can be changed immediately.
- Text selection bounds now use rendered text dimensions rather than a single placement point, placing resize and rotation controls around the actual text object.

## 2026-08-19 — rotated rectangle and text-hit correction

- Rectangles now expand to four corners before transformation, so rotation produces a true rotated shape in both the editor and saved PNG rather than an axis-aligned distorted box.
- Enlarged text hit testing so clicking within a text object reliably selects it and exposes the editable text field.

## 2026-08-19 — restored menu-bar artwork

- Bundled the supplied `img/Clipmonster.jpg` directly into the app resources and restored it as the non-template menu-bar icon.
- This avoids the current host's failing `.icns` conversion path; no alternate artwork format is required.
- Added a small checked-in ICNS packager that writes the standard PNG-backed icon chunks directly, restoring the same artwork as Finder's application-bundle icon without relying on the failing host `iconutil` conversion.

## 2026-07-23

### Unlimited capture storage & Finder reveal
- Added **Keep unlimited history** in Preferences; retention is then constrained only by available disk until the user deletes or purges items (thumbnails stay in RAM).
- Storage-folder changes now validate write access, copy the current persisted history to the chosen directory, and remove only ClipMonster-owned files from the old location.
- Added an image-row **folder** button to reveal the image PNG in Finder; temporary PNGs are created only when persistence is off.

### CLI image-path handoff (baseline behavior; 2.0 defaults changed above)
- Added an image-row **Copy Path** button.
- Added a configurable global **Paste latest image path** shortcut, default **Command–Shift–V**. It resolves a screenshot directly from the current pasteboard when needed, then pastes its PNG path into the focused CLI.
- Replaced the initial observer-based shortcut with an exclusive system hotkey so Terminal cannot paste the prior clipboard text before ClipMonster handles the command.

### Image preview & Preview.app
- Larger list thumbnails (56×56).
- In-popover **large preview overlay** (thumb click, eye button, Space).
- **Double-click** image (or ↗ button) → open PNG in **Preview.app** via `NSWorkspace`.
- Esc dismisses overlay before closing the popover.
- File rows: double-click / Space opens the file.

## 2026-07-21

### Preferences layout fix
- Settings content overflowed the fixed-height popover; Quit was unreachable.
- Preferences wrapped in `ScrollView`; header (Done + gear) and footer (Quit) pinned.
- Slightly larger popover (360×540).

### Core upgrades batch
1. Auto-paste on select (previous app + CGEvent ⌘V)  
2. Search / filter (includes OCR text)  
3. Keyboard navigation (↑/↓, Return, Esc, 1–9)  
4. Image de-dupe (SHA-256 of PNG bytes) + cleaner drag names (`clipboard-yyyy-MM-dd-HHmmss.png`)  
5. **OCR** via Apple Vision — on-demand button, optional auto-OCR, searchable + persisted  
6. Local + global shortcut monitors  
7. Temp PNG cleanup on launch (>24h)  

### Earlier same day
- Drag-out from history; Terminal-friendly file URL drag  
- Start at login (`SMAppService` / LaunchAgent fallback)  
- Docs renamed/aligned from legacy “BoarderPatrol” to **ClipMonster**  
- Documentation refresh + push to GitHub (`135f5f3`)  
- Docs re-synced for preview features (local; push when ready)

## Earlier (pre-log)

- Menu bar clipboard history (text, images, files)
- Global shortcut + recorder
- Disk persistence + purge
- Multi-select copy
- Sensitive pasteboard skip
- Initial repo: `github.com/shosho27/ClipMonster`
