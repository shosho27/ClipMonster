# Architecture: ClipMonster 2.0

## Working-copy isolation

ClipMonster 2.0 is an independent working copy created for screen-capture markup development. Keep all new feature work here; do not modify `../ClipMonster/`.

- Bundle ID: `com.sashornock.ClipMonster2`
- Default persistence: `~/Library/Application Support/ClipMonster 2.0/`
- LaunchAgent fallback: `com.sashornock.ClipMonster2`
- Temporary exports: `clipmonster2-*.png`
- Default shortcuts: Control-Option-V (popover) and Command-Option-Shift-V (latest PNG path)

Those identities prevent it from overwriting the original app's stored captures, login item, or temporary files, and avoid its initial shortcut conflicts.

## Overview

ClipMonster 2.0 is a small Swift application using **AppKit** + **SwiftUI**. It runs as a menu bar accessory (`LSUIElement`), with no Dock icon.

## Source layout

| Area | Responsibility |
|---|---|
| `src/ClipMonster.swift` | SwiftUI app entry point only |
| `src/App/` | Menu-bar lifecycle, popover, global hotkeys, auto-paste |
| `src/Models/` | Clipboard, persistence, and shortcut value types |
| `src/Services/` | Clipboard monitoring, ImageStore, disk storage, OCR, drag support, login item |
| `src/Views/` | Content shell, image preview, history, preferences, keyboard controls |
| `src/Annotation/` | Isolated markup editor, vector-like annotation model, and flattened-PNG renderer |

This boundary keeps UI state, capture/persistence work, and the annotation editor from becoming coupled in one file.

Built with `swiftc` via `build_app.sh` (links **ServiceManagement** + **Vision** + **ImageIO**). No Xcode project. On this host, `build_app.sh` also passes Xcode’s Mac SDK and SwiftUI macro plugin path so Command Line Tools `swiftc` can compile `@State`.

Bundle ID: `com.sashornock.ClipMonster2`

---

## Core components

### 1. AppDelegate (AppKit)

- Creates the `NSStatusItem` using bundled ClipMonster artwork (with an SF Symbol fallback).
- Hosts SwiftUI `ContentView` inside an `NSPopover` (default size ~360×540, transient).
- Registers **global and local** key monitors for the user-defined shortcut.
- Registers the latest-image-path shortcut as an **exclusive Carbon system hotkey**, so the focused CLI does not receive that key combination before ClipMonster substitutes the PNG path.
- Tracks `lastFrontmostApp` via `NSWorkspace.didActivateApplicationNotification` (for auto-paste).
- On drag start/end:
  - Popover → `.applicationDefined` so it stays open while dragging out.
  - On end → `.transient` and close.
- `autoPasteIntoPreviousApp()`: close popover → activate previous app → `CGEvent` ⌘V.
- `applicationWillTerminate` → `clipboardMonitor.prepareForTermination()` (save index, or delete session files when persistence is off).

### 2. ClipboardMonitor (`ObservableObject`)

- Polls `NSPasteboard.general.changeCount` every **0.5s**.
- On change, reads in order: **PNG/TIFF/image bytes** → **file URL** → **plain text**.
- Skips sensitive content (`org.nspasteboard.ConcealedType` + password-like heuristic).
- In-memory `history: [ClipboardItem]` capped by `historyLimit`, or unlimited when the user enables `unlimitedHistory`. Image rows hold a **thumbnail + PNG path**, never a decoded full screenshot.
- **De-dupe:** same text, same file URL, or same **SHA-256 of PNG file bytes** replaces the prior entry.
- Images are **always written to disk** as `<UUID>.png` in the current storage directory so RAM stays small. `index.json` is written for the live session; **`keepThroughReboot`** controls whether that index is loaded on the next launch. If persistence is off, session files are deleted on quit.
  - Default dir: `~/Library/Application Support/ClipMonster 2.0/`
  - Custom dir: `storagePath`
  - `index.json` fields: type, content, timestamp, optional `ocrText` / `imageHash` / `pixelWidth` / `pixelHeight`
- Preferences (UserDefaults): history limit/unlimited mode, auto-paste, auto-OCR, shortcut, storage path, etc.
- **`openInPreview(_:)`** — open the stored PNG with **Preview.app** (`com.apple.Preview`) via `NSWorkspace`.
- **`revealInFinder(_:)`** — select the stored image PNG in Finder.
- **`copyLatestImagePathToClipboard()`** — resolves the latest image to a PNG path; reads a just-taken screenshot from the pasteboard immediately rather than waiting for the polling interval.
- **`changeStorageDirectory(to:)`** — validates a user-selected directory, copies current PNG files, rewrites `imageFileURL`s, then removes only ClipMonster-owned files from the prior location.

### 3. ImageStore

`src/Services/ImageStore.swift` is the only place that turns pasteboard bytes into PNGs and downsamples them:

| Helper | Role |
|--------|------|
| `pngFromPasteboard` | Prefer `public.png`, else TIFF→PNG, else `NSImage`→PNG |
| `hashPNG` / `hashFile` | SHA-256 of PNG bytes (no TIFF round-trip) |
| `pixelSize` | Width/height from ImageIO properties (no full decode) |
| `thumbnail` | Max **128px** ImageIO thumbnail for the history list |
| `downsampledImage` | Max **720px** (in-app preview) or **2048px** (OCR) |

`kCGImageSourceShouldCache` is off so ImageIO does not pin decoded bitmaps.

### 4. ClipboardItem & drag export

Fields include `text`, `thumbnail`, `imageFileURL`, `fileURL`, `timestamp`, `ocrText`, `imageHash`, `isOCRing`, `pixelWidth`, `pixelHeight`. `hasImage` is true when `imageFileURL` is set. `loadFullImage()` is used only by the markup editor.

`searchableText` joins text + OCR + path components for the search field.

`makeDragItemProvider()`:

- **Images:** copy the stored PNG to a temp file named `clipmonster2-yyyy-MM-dd-HHmmss.png` (no re-encode). Provider is the file URL, plus lazily registered `public.png` data.
- **Files:** provider from existing URL.
- **Text:** `NSString` provider.

`DragSession` holds the popover open for the drag; `DragTempCleanup` removes old temp PNGs on launch.

### 5. Launch at login (`LaunchAtLogin`)

1. Prefer **`SMAppService.mainApp`** (macOS 13+ Login Items).
2. Fall back to LaunchAgent:  
   `~/Library/LaunchAgents/com.sashornock.ClipMonster2.plist`
   → `/usr/bin/open <path-to-ClipMonster 2.0.app>` at Aqua session load.

### 6. UI (SwiftUI)

| Piece | Role |
|-------|------|
| `ContentView` | Fixed header + search + flexible middle + fixed footer; hosts large-preview overlay state |
| `HistoryListView` | Empty / no-match / list with focus highlight |
| `HistoryItemRow` | 56×56 thumb from the 128px downsample; click text = copy; thumb = large preview; double-click = Preview.app; eye / ↗ / Finder / Copy Path / OCR / delete |
| `LargeImagePreviewOverlay` | Dimmed overlay; loads a ~720px downsample on appear and releases it on dismiss; Annotate loads the full PNG |
| `MarkupEditorView` | Full-size sheet launched by **Annotate**; Select, pen, arrow, box, text, color, width, undo/clear, transforms, and save |
| `PreferencesView` | **ScrollView** of settings sections (avoids clipping) |
| `HistoryKeyHandler` | Local keys: ↑/↓, Return, **Space** (preview), Esc (dismiss overlay first), 1–9 |
| `ShortcutRecorder` | Capture custom global hotkey |
| `PathPasteHotKey` | Exclusive system hotkey for pasting the newest image PNG path into the focused CLI |

**Layout rule:** Preferences content scrolls; **Done**, gear, and **Quit ClipMonster 2.0** stay pinned.

**Annotation workflow**

- Save always creates a flattened annotated copy, inserts it at the top of history, and also places it on the system clipboard. The source capture is never modified.
- Select exposes direct controls: drag to move; boxes/text/pen strokes have corner resize and rotation handles; arrows have tail/tip endpoint handles.
- The selected-object inspector provides exact color, scale, rotation, deletion, and immediate text editing.

**Image interaction split**

- Thumbnail / eye / Space → in-app large preview  
- Double-click / ↗ → `openInPreview` → Preview.app  
- Folder button → `revealInFinder` → Finder selects the PNG  
- Two-documents button → `copyImagePath` → PNG path goes to the clipboard  
- Row label area single-click → copy + optional auto-paste  

### 7. OCR (Vision)

```
on-disk PNG → ImageIO downsample (max 2048px) → CGImage
        → VNRecognizeTextRequest (accurate, language correction)
        → background queue → ocrText on ClipboardItem
```

- **On demand:** viewfinder button → `forceRunOCR`
- **Auto:** `autoOCR` preference → `runOCR` after insert (skips if already has text)
- **Copy text:** doc button → `copyOCRText` (pasteboard string, not image)
- Search includes `ocrText`; persistence stores it on image rows in `index.json`
- Fully offline; uses `import Vision` (+ CryptoKit for image hashes)

### 8. Auto-paste

When `autoPaste` is on (default **true**):

1. `copyToClipboard(item)`
2. Close popover
3. Activate `lastFrontmostApp`
4. Short delay → simulate Command+V via `CGEvent`

Requires **Accessibility**.

### 9. Global shortcut

- `CustomShortcut` (keyCode + modifiers) in UserDefaults.
- Global monitor: works in other apps (needs Accessibility).
- Local monitor: works when ClipMonster is frontmost.

---

## Data flow

```
System pasteboard change
        ↓
ClipboardMonitor.checkForChanges()
        ↓
ImageStore.pngFromPasteboard → write <UUID>.png → 128px thumbnail
        ↓
De-dupe (PNG SHA-256) + insert + save index
        ↓ optional autoOCR (2048px downsample)
        ↓
HistoryListView / HistoryItemRow (thumbnails only)
        ↓
  click text  → copy PNG bytes / text (+ auto-paste)
  thumb/Space → LargeImagePreviewOverlay (720px downsample)
  Annotate → loadFullImage → MarkupEditorView → PNG → history/storage
  double-click / ↗ → Preview.app (stored PNG)
  folder button → Finder (stored PNG)
  ⌘⌥⇧V → latest image PNG path → focused CLI
  drag        → copy stored PNG to temp → NSItemProvider (file URL)
  OCR         → 2048px downsample → Vision → ocrText
  shift       → multi-select → copySelected
```

---

## Build system

`build_app.sh`:

1. Clean/create `dist/ClipMonster 2.0.app` layout
2. `swiftc -parse-as-library` recursively compiles every Swift file below `src/`, linking ServiceManagement, Vision, and ImageIO. When Xcode.app is present, the Mac SDK and SwiftUI macro plugin path are passed so Command Line Tools `swiftc` can expand `@State`. Compile failure aborts the script.
3. Write `Info.plist` (`LSUIElement`, app icon, bundle id)
4. Bundle `Clipmonster.jpg` and generate `AppIcon.icns` with `Scripts/make_icns.swift`
5. Zip `dist/ClipMonster 2.0.zip`

`dist/` is gitignored.

---

## Not implemented (yet)

See [APP_ROADMAP.md](APP_ROADMAP.md) Phase 5: pin favorites, keep popover after drag, save image as, exclude apps, rich text, code signing/notarization.
