# ClipMonster 2.0

> **Independent working copy.** Markup, memory, and Mac App Store packaging live here. It has a distinct macOS bundle ID, application-support folder, launch-at-login label, temporary-export prefix, and default shortcuts, so it can run alongside the original **ClipMonster** without altering its files or captured history.

The original remains at `../ClipMonster/`; make feature changes in this directory only.

A lightweight **macOS menu bar clipboard manager** (macOS 14+, version **2.0.0**). Keeps a history of copied text, images, and files so you can re-copy, multi-select, search, drag them out, preview/open screenshots, OCR text, or — in the **direct** edition — auto-paste into the app you were just using.

Screenshots are stored as PNGs on disk. RAM only keeps a small thumbnail per capture (full pixels load for annotate, copy, Preview, and drag).

Built as a small Swift/AppKit/SwiftUI app. Local and direct-distribution builds use `build_app.sh`. The Mac App Store edition is `./build_app.sh mas` or the `ClipMonster-MAS` Xcode scheme (`-D MAS`, App Sandbox).

**Starting point:** [github.com/shosho27/ClipMonster](https://github.com/shosho27/ClipMonster)

---

## Features

| Area | What you get |
|------|----------------|
| History | Text, images, file URLs; optional unlimited retention |
| Memory | Disk-backed PNGs + 128px list thumbnails; not decoded screenshots |
| UI | Menu bar popover (`LSUIElement` — no Dock icon) |
| Menu bar icon | Bundled ClipMonster artwork |
| Click | Re-copy item. Direct edition: optional **auto-paste** (⌘V). Store edition: copy, then press ⌘V |
| Image preview | Larger list thumbs; **in-app overlay**; **double-click → Preview.app** |
| Annotation | Native pen, arrow, box, and text editor; saves an annotated copy without changing the source capture |
| CLI handoff | Copy an image path from a row, or a global shortcut for the latest image path (Direct types it; Store leaves it on the clipboard) |
| Search | Filter by text, filenames, and **OCR text** |
| Keyboard | ↑/↓, Return, **Space** (preview), Esc, **1–9** |
| Drag | Drop images/files/text into Finder, Terminal, design apps, etc. |
| OCR | On-device **Apple Vision** — per-image button or auto-OCR |
| De-dupe | Images by content hash; text/files by value |
| Multi-select | Shift-click → “Apply & Copy N Items” |
| Shortcut | Customizable Carbon system hotkeys (default **Control–Option–V** to open; **Command–Option–Shift–V** for the latest image path) |
| Startup | Optional **start at login** (`SMAppService`; LaunchAgent fallback in the Direct edition only) |
| Persistence | Optional history across reboots + movable custom storage directory (security-scoped bookmark when sandboxed) |
| Capture control | **Pause capture** from the header or Preferences |
| Privacy | Skips concealed / transient / auto-generated pasteboard types, known password managers, and simple password-like strings. In-app privacy policy |
| Cleanup | Purge all (with confirmation); temp drag PNGs older than 24h removed on launch |
| First launch | Welcome window points at the menu bar icon (`LSUIElement` — no Dock icon) |

---

## Requirements

- **macOS 14** or later
- Swift toolchain (`swiftc`) and `sips` for `build_app.sh`
- Xcode’s Mac SDK + SwiftUI macro plugin (used automatically by `build_app.sh` when Xcode.app is installed)
- **Accessibility** is required only in the **Direct** edition, and only for auto-paste (simulated ⌘V). Global shortcuts use Carbon hotkeys and work without Accessibility. The Mac App Store edition copies an item to the clipboard; press ⌘V to paste.

System Settings → Privacy & Security → Accessibility  
(or **Preferences → Permissions → Open System Settings** in the Direct edition)

---

## Build & run

```bash
cd "/path/to/ClipMonster 2.0"
./build_app.sh          # direct edition (auto-paste on)
./build_app.sh mas      # Store edition (sandboxed, copy then ⌘V)
open "dist/ClipMonster 2.0.app"
```

Xcode (needed for App Store archive / TestFlight):

```bash
open ClipMonster.xcodeproj
```

Schemes: **ClipMonster** (Debug/Release, direct) and **ClipMonster-MAS** (MacAppStore configuration, `-D MAS` + App Sandbox). Archive **ClipMonster-MAS** in Organizer on the **home Mac**, signed into the home Apple Developer Program team. This laptop only has a free Personal Team (`5V68L429TM`) and cannot upload to App Store Connect.

If `xcodebuild` asks you to agree to the Xcode license, run `sudo xcodebuild -license` (requires the active developer directory to be `/Applications/Xcode.app/Contents/Developer`).

Quit any already-running ClipMonster 2.0 build before opening a new build. The original ClipMonster can remain open.

**Output**

- `dist/ClipMonster 2.0.app`
- `dist/ClipMonster 2.0.zip`
(`dist/` is gitignored)

A 1024×1024 App Store icon PNG is at `Resources/AppStoreIcon.png` (upscaled from the 960px source). Replace it with a true 1024 asset on Apple's icon grid before submitting.

---

## Quick usage

1. First launch shows a welcome window: ClipMonster lives in the **menu bar** (no Dock icon).
2. Copy text, screenshots, or files as usual — they appear in ClipMonster history. Pause capture from the header pause button or Preferences if you want copies ignored.
3. Open the popover via the menu bar icon or your global shortcut (default **Control–Option–V**).
4. **Click** the row text area → copy. Direct edition auto-pastes if that preference is on; Store edition returns focus so you can press ⌘V.
5. **Drag** a row → drop into another app (Terminal gets a **file path** for images).
6. **Search** at the top; use ↑/↓ and Return without the mouse.
7. On an **image** row:
   - **Click thumbnail** or **eye** / **Space** → large in-app preview  
   - **Annotate** → pen / arrow / box / text editor → **Save Annotated Copy**
   - **Double-click** thumbnail/row or **↗** button → open in **Preview.app**  
   - **Folder** button → reveal the image PNG in **Finder**  
   - **Two documents** button → copy the image path for a CLI  
   - **Viewfinder** → run OCR · **Doc** → copy OCR text  
8. **Gear** → Preferences (scrollable; **Done** / **Quit** always visible). Purge asks for confirmation.

---

## Image preview

| Action | Result |
|--------|--------|
| Click **thumbnail** | Large overlay in the popover (~320×380) |
| **Eye** button | Same overlay |
| **Space** (focused row) | Toggle overlay (images); open file items |
| **Esc** / backdrop / Close | Dismiss overlay (Esc closes overlay before the popover) |
| **Open in Preview** (on overlay) | Hands off to Preview.app |
| **Double-click** image row/thumbnail | Opens a PNG in **Preview.app** |
| **↗ app** button | Same as double-click → Preview |
| **Folder** button | Reveal the image PNG in Finder |
| **Two documents** button | Copy the PNG's POSIX path for a CLI |
| Double-click **file** row | Opens the file in its default app |

List thumbnails are **56×56**, backed by a **128px** ImageIO downsample of the on-disk PNG. The overlay uses a **~720px** downsample, not the full screenshot. Annotate, copy, Preview.app, and drag load the original PNG.

## Annotating a capture

1. Open an image preview from its thumbnail, eye button, or Space.
2. Click **Annotate**.
3. Select the Select, Pen, Arrow, Box, or Text **icon**; the selected icon is highlighted. Choose a color and line width. Text uses the value in the Text field and is placed with a click.
4. Use **Select** (cursor icon) to click an existing annotation, then drag it to reposition it.
5. Selected text, boxes, and pen strokes show a dashed border: drag a square corner handle to resize or the round handle above it to rotate. Arrows use tail and tip handles to reshape their length and direction.
6. With an annotation selected, use its inspector to change its color, scale, rotation, or delete it.
   - Selecting text focuses an editable text field in the inspector; type to update the words.
7. Use **Undo** or **Clear** as needed, then choose **Save Annotated Copy**.

The original screenshot stays intact. **Save Annotated Copy** closes the editor and returns you to the history list, where the new flattened PNG is the first item. It is also placed on the system clipboard, follows the current persistence setting/location, and can be copied, dragged, opened in Preview, or revealed in Finder like any other capture.

---

## OCR (how it works)

OCR turns **pixels in a clipboard image** into **plain text**. It uses **Apple Vision** (`VNRecognizeTextRequest`) entirely **on-device** — no network.

| Mode | Behavior |
|------|----------|
| On demand (default) | Click the viewfinder on an image row |
| Auto-OCR | Preferences → **Auto-OCR new images** |

**Pipeline:** on-disk PNG → ImageIO downsample (max 2048px) → `CGImage` → Vision text recognition (background queue) → `ocrText` on the history item → shown under the row, searchable, optionally saved in `index.json`.

- Clicking the **row text** still copies/pastes the **image**.  
- Use the **doc** button to copy **OCR text**.  
- Best on clean UI screenshots, slides, logs; weaker on handwriting / tiny / noisy text.

More detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#7-ocr-vision).

---

## Drag behavior

- **Finder / image apps** — PNG file and/or image data  
- **Terminal** — **file path** only (not pixels). Temp name like `clipmonster2-2026-09-18-080000.png` under `$TMPDIR`

---

## Where data lives on disk

Captured images are **always written as PNG files** while the app is running, so history does not keep decoded bitmaps in RAM. `index.json` is what restores that history after a reboot.

| Mode | Location |
|------|----------|
| Session files (always) | PNGs named `<UUID>.png` in the current storage directory, plus `index.json` |
| Persistence **on** (default path) | `~/Library/Application Support/ClipMonster 2.0/` in the Direct edition; the same folder name inside the App Sandbox container in the Store edition |
| Persistence **on** (custom) | Choose a writable directory in Preferences (bookmarked for sandbox access); current history is copied there and ClipMonster's previous files are removed without touching unrelated files |
| Persistence **off** | Same PNG + index layout during the session; files are deleted on quit (and leftover files are cleared on the next launch) |
| During drag | `$TMPDIR/clipmonster2-yyyy-MM-dd-HHmmss.png` (copy of the stored PNG, not a re-encode) |

`index.json` image rows store type, filename, timestamp, and optional `ocrText` / `imageHash` / pixel size. File rows may also store a security-scoped `bookmark`. Image hashes are SHA-256 of the **PNG file bytes**.

A custom storage folder is remembered with a security-scoped bookmark so a sandboxed (Store) build can keep access after relaunch. The Store edition’s default Application Support path is inside its container.

In **Preferences → History Limits**, enable **Keep unlimited history** to retain every captured item until it is deleted or purged. Disk space is the limit; only small thumbnails stay in memory. Enable **Keep history across reboots** as well to restore that history on the next launch.

In **Preferences → Global Shortcut**, the 2.0 working copy defaults to **Control–Option–V** for opening the popover and **Command–Option–Shift–V** for the latest image path. These avoid conflicting with the original app while both are running. The shortcut captures a just-taken screenshot if necessary and puts its PNG path on the clipboard. The **Direct** edition then types that path into the focused CLI (Accessibility required). The **Store** edition leaves the path on the clipboard.

Login item: **Start at login** uses `SMAppService.mainApp`. Direct edition only, if that API fails:  
`~/Library/LaunchAgents/com.sashornock.ClipMonster2.plist`

---

## Preferences (overview)

- Pause capture  
- History limit or unlimited retention  
- Auto-paste (Direct edition) / Auto-OCR  
- Global shortcut recorder (popover + latest image path; default Command–Option–Shift–V for the path)  
- Start at login  
- Keep history across reboots + storage location  
- Permissions (Accessibility deep-link in the Direct edition; Store copy explains ⌘V)  
- Privacy policy (in-app) + version string  
- Purge all data (confirmation alert)  

UI: fixed header (pause, purge, **Done** in prefs) + **scrollable** body + fixed footer (**Quit ClipMonster 2.0**).

---

## Project layout

```
ClipMonster 2.0/
├── ClipMonster.xcodeproj  # Direct + MacAppStore schemes
├── build_app.sh           # swiftc → dist/ClipMonster 2.0.app (`mas` for Store cut)
├── Config/                # Info.plist, entitlements, privacy manifest, xcconfig
├── Resources/             # AppIcon asset catalog + 1024 App Store PNG
├── src/
│   ├── ClipMonster.swift  # App entry point
│   ├── App/               # Menu-bar lifecycle, Carbon hotkeys, welcome, MAS flag
│   ├── Annotation/        # Markup editor and flattened-PNG renderer
│   ├── Models/            # Clipboard, persistence, and shortcut data
│   ├── Services/          # Capture, ImageStore, storage, OCR, bookmarks, login, drag
│   └── Views/             # Popover, history, preview, preferences, privacy
├── Scripts/               # Deterministic ICNS packager
├── img/                   # Icon source (Clipmonster.jpg)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── APP_ROADMAP.md
│   ├── PRIVACY.md
│   └── WORK_LOG.md
├── dist/                  # Build output (gitignored)
├── .gitignore
└── README.md
```

---

## Docs

- [Architecture](docs/ARCHITECTURE.md)  
- [Roadmap](docs/APP_ROADMAP.md)  
- [Privacy policy](docs/PRIVACY.md)  
- [Work log](docs/WORK_LOG.md)  
- [Annotation module](src/Annotation/README.md)  

---

## Privacy

Clipboard history stays on this Mac. ClipMonster does not send it anywhere. See [docs/PRIVACY.md](docs/PRIVACY.md) and **Preferences → Privacy**. Host that file at an HTTPS URL before filling in App Store Connect's Privacy Policy field.

## License / status

Personal / production tooling. Two editions:

- **Direct** (`./build_app.sh`) — auto-paste and LaunchAgent fallback. Sign with Developer ID and notarize for sharing outside the Store.
- **Mac App Store** (`./build_app.sh mas` or the **ClipMonster-MAS** scheme) — App Sandbox, Carbon hotkeys, copy-then-⌘V. No synthetic keystrokes and no LaunchAgent writes.

**Status (2026-09-21):** Direct edition is the daily driver on this laptop (`dist/ClipMonster 2.0.app`, history in `~/Documents/clipmonster`). Store-shaped code is ready. **App Store archive, signing, listing, and upload wait for the home Mac** (home Developer Program account). Follow [roadmap Phase 6](docs/APP_ROADMAP.md#phase-6-sell-and-distribute-do-at-home). Direct sharing still needs Developer ID signing and notarization on that same home team.
