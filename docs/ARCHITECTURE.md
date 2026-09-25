# Architecture: ClipMonster 2.0

## Working-copy isolation

ClipMonster 2.0 is an independent working copy created for screen-capture markup development. Keep all new feature work here; do not modify `../ClipMonster/`.

- Bundle ID: `com.sashornock.ClipMonster2`
- Default persistence: `~/Library/Application Support/ClipMonster 2.0/` (inside the App Sandbox container in the Store edition)
- Login item label: `com.sashornock.ClipMonster2`
- LaunchAgent fallback (Direct edition only): `~/Library/LaunchAgents/com.sashornock.ClipMonster2.plist`
- Temporary exports: `clipmonster2-*.png`
- Default shortcuts: Control-Option-V (popover) and Command-Option-Shift-V (latest PNG path)
- Marketing version **2.0.0**, build **200**, minimum OS **macOS 14**

Those identities prevent it from overwriting the original app's stored captures, login item, or temporary files, and avoid its initial shortcut conflicts.

## Overview

ClipMonster 2.0 is a small Swift application using **AppKit** + **SwiftUI**. It runs as a menu bar accessory (`LSUIElement`), with no Dock icon. First launch shows a welcome window so that is obvious.

## Source layout

| Area | Responsibility |
|---|---|
| `src/ClipMonster.swift` | SwiftUI app entry point only |
| `src/App/` | Menu-bar lifecycle, Carbon hotkeys, welcome window, MAS vs direct (`Distribution`) |
| `src/Models/` | Clipboard, persistence, and shortcut value types |
| `src/Services/` | Capture, ImageStore, OCR, drag, login, security-scoped bookmarks, secret skipping |
| `src/Views/` | Content shell, image preview, history, preferences, privacy policy, keyboard controls |
| `src/Annotation/` | Isolated markup editor, vector-like annotation model, and flattened-PNG renderer |
| `Config/` | `Info.plist`, entitlements, `PrivacyInfo.xcprivacy`, xcconfig |
| `Resources/` | AppIcon asset catalog and 1024×1024 App Store PNG |
| `ClipMonster.xcodeproj` | Direct (Debug/Release) and MacAppStore schemes |

This boundary keeps UI state, capture/persistence work, and the annotation editor from becoming coupled in one file.

Built with `swiftc` via `build_app.sh` (links **ServiceManagement** + **Vision** + **ImageIO** + **Carbon**) or with `ClipMonster.xcodeproj`. On this host, `build_app.sh` also passes Xcode’s Mac SDK and SwiftUI macro plugin path so Command Line Tools `swiftc` can compile `@State`.

Two editions share the same sources:

| Edition | Flag | Entitlements | Paste | Login item |
|---|---|---|---|---|
| Direct (`./build_app.sh`, Debug/Release) | none | `Config/ClipMonster.entitlements` | Copy + optional synthetic ⌘V | `SMAppService`, then LaunchAgent fallback |
| Mac App Store (`./build_app.sh mas`, MacAppStore) | `-D MAS` | `Config/ClipMonsterMAS.entitlements` (sandbox + user-selected files) | Copy, then the user presses ⌘V | `SMAppService` only |

`Distribution.supportsAutoPaste` is false in Store binaries and whenever the process is sandboxed. Carbon `RegisterEventHotKey` drives both global shortcuts so they work without Accessibility.

---

## Core components

### 1. AppDelegate (AppKit)

- Creates the `NSStatusItem` using bundled ClipMonster artwork (with an SF Symbol fallback). The button appears disabled while capture is paused.
- Hosts SwiftUI `ContentView` inside an `NSPopover` (default size ~360×540, transient).
- Registers both the popover shortcut and the latest-image-path shortcut with Carbon `RegisterEventHotKey` (`src/App/CarbonHotKey.swift`). The path-paste hotkey is exclusive in the Direct edition (`kEventHotKeyExclusive` is compiled out of Store binaries).
- Unregisters hotkeys while the shortcut recorder is capturing a new combination.
- First launch shows `WelcomeWindowController` so a menu-bar-only app is findable.
- Tracks `lastFrontmostApp` via `NSWorkspace.didActivateApplicationNotification`.
- On drag start/end:
  - Popover → `.applicationDefined` so it stays open while dragging out.
  - On end → `.transient` and close.
- `autoPasteIntoPreviousApp()` (Direct): close popover → activate previous app → `CGEvent` ⌘V.
- `handFocusBackAfterCopy()` (Store, and Direct when auto-paste is off): close popover → activate previous app, no synthetic keys.
- `applicationWillTerminate` → unregister hotkeys, then `clipboardMonitor.prepareForTermination()`.

### 2. ClipboardMonitor (`ObservableObject`)

- Polls `NSPasteboard.general.changeCount` every **0.5s**.
- `capturePaused`: new copies are ignored (the change count is still consumed so a burst does not flood in on resume).
- On change, reads in order: **PNG/TIFF/image bytes** → **file URL** → **plain text**.
- Skips via `SensitiveCapture`: concealed / transient / auto-generated pasteboard types, known password-manager bundle IDs when frontmost, and a password-like string heuristic.
- In-memory `history: [ClipboardItem]` capped by `historyLimit`, or unlimited when the user enables `unlimitedHistory`. Image rows hold a **thumbnail + PNG path**, never a decoded full screenshot.
- **De-dupe:** same text, same file URL, or same **SHA-256 of PNG file bytes** replaces the prior entry.
- Images are **always written to disk** as `<UUID>.png` in the current storage directory so RAM stays small. `index.json` is written for the live session; **`keepThroughReboot`** controls whether that index is loaded on the next launch. If persistence is off, session files are deleted on quit.
  - Default dir: Application Support `ClipMonster 2.0` (container path when sandboxed)
  - Custom dir: `storagePath` plus a security-scoped bookmark in UserDefaults
  - `index.json` fields: type, content, timestamp, optional `ocrText` / `imageHash` / `pixelWidth` / `pixelHeight` / `bookmark`
- Preferences (UserDefaults): history limit/unlimited mode, pause, auto-paste, auto-OCR, shortcuts, storage path, welcome flag, storage bookmark.
- **`openInPreview(_:)`** — open the stored PNG with **Preview.app** (`com.apple.Preview`) via `NSWorkspace`. File clips use `resolvedFileURL()` so bookmarks are honored.
- **`revealInFinder(_:)`** — select the stored image PNG (or resolved file) in Finder.
- **`copyLatestImagePathToClipboard()`** — resolves the latest image to a PNG path; reads a just-taken screenshot from the pasteboard immediately rather than waiting for the polling interval.
- **`changeStorageDirectory(to:)`** — validates a user-selected directory, copies current PNG files, saves a security-scoped bookmark, rewrites `imageFileURL`s, then removes only ClipMonster-owned files from the prior location.

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

Fields include `text`, `thumbnail`, `imageFileURL`, `fileURL`, `fileBookmark`, `timestamp`, `ocrText`, `imageHash`, `isOCRing`, `pixelWidth`, `pixelHeight`. `hasImage` is true when `imageFileURL` is set. `loadFullImage()` is used only by the markup editor. `resolvedFileURL()` prefers a security-scoped bookmark.

`searchableText` joins text + OCR + path components for the search field.

`makeDragItemProvider()`:

- **Images:** copy the stored PNG to a temp file named `clipmonster2-yyyy-MM-dd-HHmmss.png` (no re-encode). Provider is the file URL, plus lazily registered `public.png` data.
- **Files:** provider from `resolvedFileURL()`.
- **Text:** `NSString` provider.

`DragSession` holds the popover open for the drag (global/local left-mouse-up monitors). `DragTempCleanup` removes old temp PNGs on launch.

### 5. Launch at login (`LaunchAtLogin`)

1. **`SMAppService.mainApp`** Login Items (macOS 13+, deployment target 14).
2. Direct edition only: fall back to LaunchAgent  
   `~/Library/LaunchAgents/com.sashornock.ClipMonster2.plist`  
   → `/usr/bin/open <path-to-ClipMonster 2.0.app>` at Aqua session load.  
   That fallback is compiled out of Store binaries.

### 6. UI (SwiftUI)

| Piece | Role |
|-------|------|
| `ContentView` | Fixed header + search + flexible middle + fixed footer; pause, purge confirm, large-preview overlay |
| `WelcomeView` | One-time first-launch window (`hasSeenWelcome`) |
| `HistoryListView` | Empty / paused / no-match / list with focus highlight |
| `HistoryItemRow` | 56×56 thumb from the 128px downsample; click text = copy; thumb = large preview; double-click = Preview.app; eye / ↗ / Finder / Copy Path / OCR / delete |
| `LargeImagePreviewOverlay` | Dimmed overlay; loads a ~720px downsample on appear and releases it on dismiss; Annotate loads the full PNG |
| `MarkupEditorView` | Full-size sheet launched by **Annotate**; Select, pen, arrow, box, text, color, width, undo/clear, transforms, and save |
| `PreferencesView` | **ScrollView** of settings; Direct shows auto-paste + Accessibility; Store explains copy-then-⌘V |
| `PrivacyPolicyView` | In-app policy (same facts as `docs/PRIVACY.md`) |
| `HistoryKeyHandler` | Local keys: ↑/↓, Return, **Space** (preview), Esc (dismiss overlay first), 1–9 |
| `ShortcutRecorder` | Capture a custom hotkey; posts recording began/ended so Carbon hotkeys stand down |
| `CarbonHotKeyCenter` | System-wide popover + path-paste hotkeys |

**Layout rule:** Preferences content scrolls; **Done**, gear, and **Quit ClipMonster 2.0** stay pinned. Pause and purge sit in the history header.

**Annotation workflow**

- Save always creates a flattened annotated copy, inserts it at the top of history, and also places it on the system clipboard. The source capture is never modified.
- Select exposes direct controls: drag to move; boxes/text/pen strokes have corner resize and rotation handles; arrows have tail/tip endpoint handles.
- The selected-object inspector provides exact color, scale, rotation, deletion, and immediate text editing.

**Image interaction split**

- Thumbnail / eye / Space → in-app large preview  
- Double-click / ↗ → `openInPreview` → Preview.app  
- Folder button → `revealInFinder` → Finder selects the PNG  
- Two-documents button → `copyImagePath` → PNG path goes to the clipboard  
- Row label area single-click → copy, then auto-paste (Direct) or hand focus back (Store)

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

Direct edition, when `autoPaste` is on (default **true**):

1. `copyToClipboard(item)`
2. Close popover
3. Activate `lastFrontmostApp`
4. Short delay → simulate Command+V via `CGEvent`

Requires **Accessibility**. `CGEvent.post` is compiled out of Store binaries (`#if !MAS`). The Store edition copies, closes the popover, and activates the previous app so ⌘V goes to the right place.

### 9. Global shortcut

- `CustomShortcut` (keyCode + modifiers) in UserDefaults.
- Carbon `RegisterEventHotKey` for the popover (`id` 1) and for path-paste (`id` 2), signature `CLM2`.
- Shortcut recording unregisters hotkeys so the recorder can capture the key.

### 10. Sandbox and bookmarks (`ScopedBookmarks`)

Store binaries enable App Sandbox plus `com.apple.security.files.user-selected.read-write`.

- Custom storage folder: bookmark in UserDefaults (`storageFolderBookmark`); `startAccessingSecurityScopedResource` for the session.
- File clips: bookmark bytes on `ClipboardItem.fileBookmark` / `PersistedItem.bookmark`, resolved on open, reveal, copy, and drag.

---

## Data flow

```
System pasteboard change
        ↓
ClipboardMonitor.checkForChanges()
        ↓ skip if paused or SensitiveCapture.shouldSkip
        ↓
ImageStore.pngFromPasteboard → write <UUID>.png → 128px thumbnail
  (or file URL + bookmark, or text)
        ↓
De-dupe (PNG SHA-256) + insert + save index
        ↓ optional autoOCR (2048px downsample)
        ↓
HistoryListView / HistoryItemRow (thumbnails only)
        ↓
  click text  → copy PNG bytes / text
                Direct + autoPaste → CGEvent ⌘V
                otherwise → hand focus back (user presses ⌘V)
  thumb/Space → LargeImagePreviewOverlay (720px downsample)
  Annotate → loadFullImage → MarkupEditorView → PNG → history/storage
  double-click / ↗ → Preview.app (stored PNG)
  folder button → Finder (stored PNG)
  ⌘⌥⇧V → latest image PNG path on clipboard
          Direct → synthetic ⌘V into focused CLI
  drag        → copy stored PNG to temp → NSItemProvider (file URL)
  OCR         → 2048px downsample → Vision → ocrText
  shift       → multi-select → copySelected
```

---

## Build system

`build_app.sh` (optional argument `mas`):

1. Clean/create `dist/ClipMonster 2.0.app` layout
2. `swiftc -parse-as-library` recursively compiles every Swift file below `src/`, targeting **macOS 14**, linking ServiceManagement, Vision, ImageIO, and Carbon. `mas` adds `-D MAS`. When Xcode.app is present, the Mac SDK and SwiftUI macro plugin path are passed so Command Line Tools `swiftc` can expand `@State`. Compile failure aborts the script.
3. Install `Config/Info.plist` and `Config/PrivacyInfo.xcprivacy`
4. Bundle `Clipmonster.jpg` and generate `AppIcon.icns` with `Scripts/make_icns.swift`
5. Ad-hoc sign; `mas` also applies `Config/ClipMonsterMAS.entitlements` (App Sandbox)
6. Zip `dist/ClipMonster 2.0.zip`

`ClipMonster.xcodeproj` is the App Store / TestFlight path: scheme **ClipMonster-MAS**, configuration **MacAppStore**. Debug/Release schemes build the Direct edition. Archive and upload from the **home Mac** on the home Developer Program team. This laptop’s signing identity is a free Personal Team (`DEVELOPMENT_TEAM = 5V68L429TM` in `Config/Common.xcconfig`); override that team in Xcode at home. `xcodebuild` needs the Xcode license accepted and the active developer directory set to Xcode.app.

`Info.plist` includes `LSUIElement`, `LSMinimumSystemVersion` 14.0, `ITSAppUsesNonExemptEncryption` false, productivity category, and copyright. `PrivacyInfo.xcprivacy` declares UserDefaults (`CA92.1`) and file-timestamp (`C617.1`) access, with tracking off.

`dist/` is gitignored.

---

## Not implemented (yet)

See [APP_ROADMAP.md](APP_ROADMAP.md) Phase 5 leftovers (pin, save-as, exclude-app picker, rich text) and Phase 6 (App Store archive and listing **at home** on the home Developer Program account).
