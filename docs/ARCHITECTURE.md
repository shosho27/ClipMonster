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
- Tracks `lastFrontmostApp` via `NSWorkspace.didActivateApplicationNotification` (for auto-paste).
- On drag start/end:
  - Popover → `.applicationDefined` so it stays open while dragging out.
  - On end → `.transient` and close.
- `autoPasteIntoPreviousApp()`: close popover → activate previous app → `CGEvent` ⌘V.

### 2. ClipboardMonitor (`ObservableObject`)

- Polls `NSPasteboard.general.changeCount` every **0.5s**.
- On change, reads in order: **image** → **file URL** → **plain text**.
- Skips sensitive content (`org.nspasteboard.ConcealedType` + password-like heuristic).
- In-memory `history: [ClipboardItem]` capped by `historyLimit`.
- **De-dupe:** same text, same file URL, or same **image SHA-256** replaces the prior entry.
- Optional disk persistence (`keepThroughReboot`):
  - PNG per image: `~/Library/Application Support/ClipMonster/<UUID>.png` (or custom `storagePath`)
  - `index.json` with type, content, timestamp, optional `ocrText` / `imageHash`
- Preferences (UserDefaults): history limit, auto-paste, auto-OCR, shortcut, storage path, etc.

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
| `ContentView` | Fixed header + optional search + flexible middle + fixed footer (Quit) |
| `HistoryListView` | Empty / no-match / list with focus highlight |
| `HistoryItemRow` | Thumbnail; click activate; drag; OCR controls; Shift multi-select; delete |
| `PreferencesView` | **ScrollView** of settings sections (avoids clipping) |
| `HistoryKeyHandler` | Local key monitor: ↑/↓, Return, Esc, 1–9 |
| `ShortcutRecorder` | Capture custom global hotkey |

**Layout rule:** Preferences content scrolls; **Done**, gear, and **Quit ClipMonster** stay pinned so controls are never cut off.

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
  click  → copy (+ auto-paste)
  drag   → NSItemProvider (file URL + image)
  OCR    → Vision → ocrText → search / copy text
  shift  → multi-select → copySelected
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

See [APP_ROADMAP.md](APP_ROADMAP.md) Phase 5: pin favorites, large preview, keep popover after drag, reveal/save path, exclude apps, rich text, code signing/notarization.
