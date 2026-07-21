# ClipMonster

A lightweight **macOS menu bar clipboard manager**. Keeps a history of copied text, images, and files so you can re-copy, multi-select, search, drag them out, OCR screenshots, or auto-paste into the app you were just using.

Built as a **single-file** Swift/SwiftUI app (no Xcode project). Compiled locally with `build_app.sh`.

**Repo:** [github.com/shosho27/ClipMonster](https://github.com/shosho27/ClipMonster)

---

## Features

| Area | What you get |
|------|----------------|
| History | Text, images, file URLs |
| UI | Menu bar popover (`LSUIElement` — no Dock icon) |
| Click | Re-copy item; optional **auto-paste** (⌘V into previous app) |
| Search | Filter by text, filenames, and **OCR text** |
| Keyboard | ↑/↓ focus, Return activate, Esc close, **1–9** jump |
| Drag | Drop images/files/text into Finder, Terminal, design apps, etc. |
| OCR | On-device **Apple Vision** — per-image button or auto-OCR |
| De-dupe | Images by content hash; text/files by value |
| Multi-select | Shift-click → “Apply & Copy N Items” |
| Shortcut | Customizable global hotkey (default **Fn+V**); local + global monitors |
| Startup | Optional **start at login** |
| Persistence | Optional history across reboots + custom storage path |
| Privacy | Skips concealed pasteboard types / simple password-like strings |
| Cleanup | Purge all; temp drag PNGs older than 24h removed on launch |

---

## Requirements

- macOS with Swift toolchain (`swiftc`) and standard CLI tools (`sips`, `iconutil`)
- **Accessibility** permission for:
  - Global shortcut while other apps are focused
  - Auto-paste (simulated ⌘V)

System Settings → Privacy & Security → Accessibility  
(or use **Preferences → Permissions → Open System Settings** in the app)

---

## Build & run

```bash
cd /path/to/ClipMonster
./build_app.sh
open dist/ClipMonster.app
```

Quit any already-running ClipMonster before opening a new build.

**Output**

- `dist/ClipMonster.app`
- `dist/ClipMonster.zip`  
(`dist/` is gitignored)

---

## Quick usage

1. Copy text, screenshots, or files as usual — they appear in ClipMonster history.
2. Open the popover via the menu bar icon or your global shortcut.
3. **Click** a row → copy (and auto-paste if enabled).
4. **Drag** a row → drop into another app (Terminal gets a **file path** for images).
5. **Search** at the top; use ↑/↓ and Return without the mouse.
6. On an **image** row:
   - **Viewfinder** icon → run OCR  
   - **Doc** icon → copy extracted text  
7. **Gear** → Preferences (scrollable; **Done** / **Quit** always visible).

---

## OCR (how it works)

OCR turns **pixels in a clipboard image** into **plain text**. It uses **Apple Vision** (`VNRecognizeTextRequest`) entirely **on-device** — no network.

| Mode | Behavior |
|------|----------|
| On demand (default) | Click the viewfinder on an image row |
| Auto-OCR | Preferences → **Auto-OCR new images** |

**Pipeline:** `NSImage` → `CGImage` → Vision text recognition (background queue) → `ocrText` on the history item → shown under the row, searchable, optionally saved in `index.json`.

- Clicking the **row** still copies/pastes the **image**.  
- Use the **doc** button to copy **OCR text**.  
- Best on clean UI screenshots, slides, logs; weaker on handwriting / tiny / noisy text.

More detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#6-ocr-vision).

---

## Drag behavior

- **Finder / image apps** — PNG file and/or image data  
- **Terminal** — **file path** only (not pixels). Temp name like `clipboard-2026-07-21-143022.png` under `$TMPDIR`

---

## Where data lives on disk

| Mode | Location |
|------|----------|
| Persistence **off** | Memory only |
| Persistence **on** (default) | `~/Library/Application Support/ClipMonster/<UUID>.png` + `index.json` (includes `ocrText` / `imageHash` for images) |
| Persistence **on** (custom) | `<your path>/…` |
| During drag | `$TMPDIR/clipboard-*.png` (and legacy `ClipMonster-*.png`) |

Login agent (fallback path):  
`~/Library/LaunchAgents/com.sashornock.ClipMonster.plist`

---

## Preferences (overview)

- History limit  
- Auto-paste / Auto-OCR  
- Global shortcut recorder  
- Start at login  
- Keep history across reboots + storage location  
- Accessibility deep-link  
- Purge all data  

UI: fixed header (**Done** in prefs) + **scrollable** body + fixed footer (**Quit ClipMonster**).

---

## Project layout

```
ClipMonster/
├── build_app.sh           # swiftc → dist/ClipMonster.app (+ Vision, ServiceManagement)
├── src/ClipMonster.swift  # Entire app
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

Personal / production tooling. Not notarized by default — for local use or ad-hoc sharing via `dist/ClipMonster.zip`.
