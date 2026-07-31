# Architecture: ClipMonster

## Overview

ClipMonster is a **single-file** Swift application (`src/ClipMonster.swift`) using **AppKit** + **SwiftUI**. It runs as a menu bar accessory (`LSUIElement`), with no Dock icon.

Built with `swiftc` via `build_app.sh` (links **ServiceManagement** + **Vision**). No Xcode project.

Bundle ID: `com.sashornock.ClipMonster`

---

## Core components

### 1. AppDelegate (AppKit)

- Creates the `NSStatusItem` (menu bar icon).
- Hosts SwiftUI `ContentView` inside an `NSPopover` (default size ~360×540, transient).
- Registers **global and local** key monitors for the user-defined shortcut.
- Registers the latest-image-path shortcut as an **exclusive Carbon system hotkey**, so the focused CLI does not receive that key combination before ClipMonster substitutes the PNG path.
- Tracks `lastFrontmostApp` via `NSWorkspace.didActivateApplicationNotification` (for auto-paste).
- On drag start/end:
  - Popover → `.applicationDefined` so it stays open while dragging out.
  - On end → `.transient` and close.
- `autoPasteIntoPreviousApp()`: close popover → activate previous app → `CGEvent` ⌘V.

### 2. ClipboardMonitor (`ObservableObject`)

- Polls `NSPasteboard.general.changeCount` every **0.5s**.
- On change, reads in order: **image** → **file URL** → **plain text**.
- Skips sensitive content (`org.nspasteboard.ConcealedType` + password-like heuristic).
- In-memory `history: [ClipboardItem]` capped by `historyLimit`, or unlimited when the user enables `unlimitedHistory`.
- **De-dupe:** same text, same file URL, or same **image SHA-256** replaces the prior entry.
- Optional disk persistence (`keepThroughReboot`):
  - PNG per image: `~/Library/Application Support/ClipMonster/<UUID>.png` (or custom `storagePath`)
  - `index.json` with type, content, timestamp, optional `ocrText` / `imageHash`
- Preferences (UserDefaults): history limit/unlimited mode, auto-paste, auto-OCR, shortcut, storage path, etc.
- **`openInPreview(_:)`** — resolve/write PNG (persisted path preferred), open with **Preview.app** (`com.apple.Preview`) via `NSWorkspace`.
- **`revealInFinder(_:)`** — select a persisted (or temporary) image PNG in Finder.
- **`copyLatestImagePathToClipboard()`** — resolves the latest image to a PNG path; reads a just-taken screenshot from the pasteboard immediately rather than waiting for the polling interval.
- **`changeStorageDirectory(to:)`** — validates a user-selected directory, copies the current persisted history, then removes only ClipMonster-owned files from the prior location.

### 3. ClipboardItem & drag export

Fields include `text`, `image`, `fileURL`, `timestamp`, `ocrText`, `imageHash`, `isOCRing`.

`searchableText` joins text + OCR + path components for the search field.

`makeDragItemProvider()`:

- **Images:** write temp PNG named `clipboard-yyyy-MM-dd-HHmmss.png`, base provider on **file URL** (Terminal/Finder), plus `public.png` data and `NSImage`.
- **Files:** provider from existing URL.
- **Text:** `NSString` provider.

`DragSession` holds the popover open for the drag; `DragTempCleanup` removes old temp PNGs on launch.

### 4. Launch at login (`LaunchAtLogin`)

1. Prefer **`SMAppService.mainApp`** (macOS 13+ Login Items).
2. Fall back to LaunchAgent:  
   `~/Library/LaunchAgents/com.sashornock.ClipMonster.plist`  
   → `/usr/bin/open <path-to-ClipMonster.app>` at Aqua session load.

### 5. UI (SwiftUI)

| Piece | Role |
|-------|------|
| `ContentView` | Fixed header + search + flexible middle + fixed footer; hosts large-preview overlay state |
| `HistoryListView` | Empty / no-match / list with focus highlight |
| `HistoryItemRow` | 56×56 thumb; click text = copy; thumb = large preview; double-click = Preview.app; eye / ↗ / Finder / Copy Path / OCR / delete |
| `LargeImagePreviewOverlay` | Dimmed overlay with large image, optional OCR snippet, Open in Preview / Close |
| `PreferencesView` | **ScrollView** of settings sections (avoids clipping) |
| `HistoryKeyHandler` | Local keys: ↑/↓, Return, **Space** (preview), Esc (dismiss overlay first), 1–9 |
| `ShortcutRecorder` | Capture custom global hotkey |
| `PathPasteHotKey` | Exclusive system hotkey for pasting the newest image PNG path into the focused CLI |

**Layout rule:** Preferences content scrolls; **Done**, gear, and **Quit ClipMonster** stay pinned.

**Image interaction split**

- Thumbnail / eye / Space → in-app large preview  
- Double-click / ↗ → `openInPreview` → Preview.app  
- Folder button → `revealInFinder` → Finder selects the PNG  
- Two-documents button → `copyImagePath` → PNG path goes to the clipboard  
- Row label area single-click → copy + optional auto-paste  

### 6. OCR (Vision)

```
NSImage → CGImage → VNRecognizeTextRequest (accurate, language correction)
        → background queue → ocrText on ClipboardItem
```

- **On demand:** viewfinder button → `forceRunOCR`
- **Auto:** `autoOCR` preference → `runOCR` after insert (skips if already has text)
- **Copy text:** doc button → `copyOCRText` (pasteboard string, not image)
- Search includes `ocrText`; persistence stores it on image rows in `index.json`
- Fully offline; uses `import Vision` (+ CryptoKit for image hashes)

### 7. Auto-paste

When `autoPaste` is on (default **true**):

1. `copyToClipboard(item)`
2. Close popover
3. Activate `lastFrontmostApp`
4. Short delay → simulate Command+V via `CGEvent`

Requires **Accessibility**.

### 8. Global shortcut

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
De-dupe + insert (+ optional disk save)
        ↓ optional autoOCR
        ↓
HistoryListView / HistoryItemRow
        ↓
  click text  → copy (+ auto-paste)
  thumb/Space → LargeImagePreviewOverlay
  double-click / ↗ → Preview.app (openInPreview)
  folder button → Finder (revealInFinder)
  ⌘⇧V → latest image PNG path → focused CLI
  drag        → NSItemProvider (file URL + image)
  OCR         → Vision → ocrText → search / copy text
  shift       → multi-select → copySelected
```

---

## Build system

`build_app.sh`:

1. Clean/create `dist/ClipMonster.app` layout  
2. `swiftc -parse-as-library src/*.swift -framework ServiceManagement -framework Vision`  
3. Write `Info.plist` (`LSUIElement`, icon, bundle id)  
4. Generate `AppIcon.icns` from `img/Clipmonster.jpg`  
5. Zip `dist/ClipMonster.zip`  

`dist/` is gitignored.

---

## Not implemented (yet)

See [APP_ROADMAP.md](APP_ROADMAP.md) Phase 5: pin favorites, keep popover after drag, save image as, exclude apps, rich text, code signing/notarization.
