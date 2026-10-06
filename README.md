# ClipMonster 2.0

> **Independent working copy.** This is the sandbox for the markup/annotation work. It has a distinct macOS bundle ID, application-support folder, launch-at-login label, temporary-export prefix, and default shortcuts, so it can run alongside the original **ClipMonster** without altering its files or captured history.

The original remains at `../ClipMonster/`; make feature changes in this directory only.

A lightweight **macOS menu bar clipboard manager**. Keeps a history of copied text, images, and files so you can re-copy, multi-select, search, drag them out, preview/open screenshots, OCR text, or auto-paste into the app you were just using.

Screenshots are stored as PNGs on disk. RAM only keeps a small thumbnail per capture (full pixels load for annotate, copy, Preview, and drag).

Built as a small Swift/AppKit/SwiftUI app (no Xcode project). Compiled locally with `build_app.sh`.

**Starting point:** [github.com/shosho27/ClipMonster](https://github.com/shosho27/ClipMonster)

---

## Features

| Area | What you get |
|------|----------------|
| History | Text, images, file URLs; optional unlimited retention |
| Memory | Disk-backed PNGs + 128px list thumbnails; not decoded screenshots |
| UI | Menu bar popover (`LSUIElement` — no Dock icon) |
| Menu bar icon | Bundled ClipMonster artwork |
| Click | Re-copy item; optional **auto-paste** (⌘V into previous app) |
| Image preview | Larger list thumbs; **in-app overlay**; **double-click → Preview.app** |
| Annotation | Native pen, arrow, box, and text editor; saves an annotated copy without changing the source capture |
| Scrolling capture | Select content in an open browser; automatically scroll and stitch a tall PNG into history and the clipboard |
| CLI handoff | Copy an image path manually or paste the latest image path with a global shortcut |
| Search | Filter by text, filenames, and **OCR text** |
| Keyboard | ↑/↓, Return, **Space** (preview), Esc, **1–9** |
| Drag | Drop images/files/text into Finder, Terminal, design apps, etc. |
| OCR | On-device **Apple Vision** — per-image button or auto-OCR |
| De-dupe | Images by content hash; text/files by value |
| Multi-select | Shift-click → “Apply & Copy N Items” |
| Shortcut | Customizable global hotkey (default **Control–Option–V**); local + global monitors |
| Startup | Optional **start at login** |
| Persistence | Optional history across reboots + safely movable custom storage directory |
| Privacy | Skips concealed pasteboard types / simple password-like strings |
| Cleanup | Purge all; temp drag PNGs older than 24h removed on launch |

---

## Requirements

- macOS with the Swift toolchain (`swiftc`) and `sips`
- Xcode’s Mac SDK + SwiftUI macro plugin (used automatically by `build_app.sh` when Xcode.app is installed)
- **Accessibility** permission for:
  - Global shortcut while other apps are focused
  - Auto-paste (simulated ⌘V)

System Settings → Privacy & Security → Accessibility  
(or use **Preferences → Permissions → Open System Settings** in the app)

---

## Build & run

```bash
cd "/path/to/ClipMonster 2.0"
./build_app.sh
open "dist/ClipMonster 2.0.app"
```

Quit any already-running ClipMonster 2.0 build before opening a new build. The original ClipMonster can remain open.

**Output**

- `dist/ClipMonster 2.0.app`
- `dist/ClipMonster 2.0.zip`
(`dist/` is gitignored)

---

## Quick usage

1. Copy text, screenshots, or files as usual — they appear in ClipMonster history.
2. Open the popover via the menu bar icon or your global shortcut.
3. **Click** the row text area → copy (and auto-paste if enabled).
4. **Drag** a row → drop into another app (Terminal gets a **file path** for images).
5. **Search** at the top; use ↑/↓ and Return without the mouse.
6. On an **image** row:
   - **Click thumbnail** or **eye** / **Space** → large in-app preview  
   - **Annotate** → pen / arrow / box / text editor → **Save Annotated Copy**
   - **Double-click** thumbnail/row or **↗** button → open in **Preview.app**  
   - **Folder** button → reveal the image PNG in **Finder**  
   - **Two documents** button → copy the image path for a CLI  
   - **Viewfinder** → run OCR · **Doc** → copy OCR text  
7. **Gear** → Preferences (scrollable; **Done** / **Quit** always visible).

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

## Scrolling webpage capture

1. Bring the browser containing your webpage to the front and scroll to the top (or the position you want to start from).
2. Open ClipMonster and click **Scrolling Capture**, then **Select Webpage Area**.
3. Drag a rectangle around the scrolling page content on one display. Exclude browser toolbars, fixed/sticky headers, and scrollbars. The minimum selection is 200 × 150 points.
4. Keep the browser focused, visible, and stationary. ClipMonster scrolls the content under the center of your selection and captures overlapping viewports. A small control panel is hidden while taking each screenshot.
5. Capture ends after three scroll attempts no longer change the selected content. **Stop & Save** saves the captured portion at any time; **Cancel** or **Escape** discards it. A successful capture becomes one tall PNG in history and on the clipboard, with the same preview, annotation, OCR, persistence, and export behavior as other images.

Enable **Accessibility** and **Screen & System Audio Recording** for ClipMonster 2.0 in System Settings → Privacy & Security when prompted. Screen permission changes may require restarting ClipMonster. No browser extension, JavaScript setting, or page reload is required; screenshots capture the browser's current logged-in state.

The selected area's pixels determine alignment and when scrolling has stopped; this does not inspect the browser DOM or guarantee the document bottom on blank/repeating content, nested scrollers, or pages that intercept scrolling. Choose the actual scrolling content. Fixed elements and animations can interfere with stitching. Lazy images get a settling delay, but very slow content may need a second attempt. Infinite pages are bounded at two minutes, 100 frames, 30,000 pixels tall, or 60 megapixels. Alignment failures and limits save a clearly labeled **partial capture**, instead of inventing a seam. Focus changes or capture/storage errors discard the attempt. The browser remains at its final scroll position; the mouse pointer returns to its starting position.

Run the deterministic alignment/composition checks with:

```bash
swiftc src/Services/ScrollCaptureStitcher.swift Tests/ScrollCaptureStitcherTests.swift -o /tmp/clipmonster-scroll-tests
/tmp/clipmonster-scroll-tests
```

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
| Persistence **on** (default path) | `~/Library/Application Support/ClipMonster 2.0/` — restored on next launch |
| Persistence **on** (custom) | Choose a writable directory in Preferences; current history is copied there and ClipMonster's previous files are removed without touching unrelated files |
| Persistence **off** | Same PNG + index layout during the session; files are deleted on quit (and leftover files are cleared on the next launch) |
| During drag | `$TMPDIR/clipmonster2-yyyy-MM-dd-HHmmss.png` (copy of the stored PNG, not a re-encode) |

`index.json` image rows store type, filename, timestamp, and optional `ocrText` / `imageHash` / pixel size. Image hashes are SHA-256 of the **PNG file bytes**.

In **Preferences → History Limits**, enable **Keep unlimited history** to retain every captured item until it is deleted or purged. Disk space is the limit; only small thumbnails stay in memory. Enable **Keep history across reboots** as well to restore that history on the next launch.

In **Preferences → Global Shortcut**, the 2.0 working copy defaults to **Control–Option–V** for opening the popover and **Command–Option–Shift–V** for pasting the latest image path. These avoid conflicting with the original app while both are running. It captures a just-taken screenshot if necessary, puts its PNG path on the clipboard, and types that path into the focused terminal or other CLI application. Accessibility permission is required.

Login agent (fallback path):  
`~/Library/LaunchAgents/com.sashornock.ClipMonster2.plist`

---

## Preferences (overview)

- History limit or unlimited retention  
- Auto-paste / Auto-OCR  
- Global shortcut recorder  
- Latest-image-path paste shortcut (default Command–Option–Shift–V)
- Start at login  
- Keep history across reboots + storage location  
- Image-row Finder reveal  
- Accessibility deep-link  
- Purge all data  

UI: fixed header (**Done** in prefs) + **scrollable** body + fixed footer (**Quit ClipMonster 2.0**).

---

## Project layout

```
ClipMonster 2.0/
├── build_app.sh           # swiftc → dist/ClipMonster 2.0.app (+ Vision, ServiceManagement, ImageIO)
├── src/
│   ├── ClipMonster.swift  # App entry point
│   ├── App/               # Menu-bar lifecycle and shortcut registration
│   ├── Annotation/        # Markup editor and flattened-PNG renderer
│   ├── Models/            # Clipboard, persistence, and shortcut data
│   ├── Services/          # Capture, ImageStore, storage, OCR, exports, login, drag
│   └── Views/             # Popover, history, preview, preferences, controls
├── Scripts/                # Deterministic ICNS packager
├── img/                   # Icon source (Clipmonster.jpg)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── APP_ROADMAP.md
│   └── WORK_LOG.md
├── dist/                  # Build output (gitignored)
├── .gitignore
└── README.md
```

---

## Docs

- [Architecture](docs/ARCHITECTURE.md)  
- [Roadmap](docs/APP_ROADMAP.md)  
- [Work log](docs/WORK_LOG.md)  

---

## License / status

Personal / production tooling. Not notarized by default — for local use or ad-hoc sharing via `dist/ClipMonster 2.0.zip`.
