# BoarderPatrol

A lightweight, powerful macOS menu bar clipboard manager that "patrols your pasteboard."

## What It Is

BoarderPatrol is a native macOS Swift/SwiftUI application built to maintain a history of your clipboard. It runs completely in the background as a menu bar accessory, preventing you from ever losing copied text, images, or files again.

The app is built from source locally using a standalone build script, without the need for an Xcode project overhead.

The current app plan includes:

- In-memory clipboard history (dumps on restart for privacy/performance)
- Support for Text, Images, Rich Text, and File Paths
- Global customizable keyboard shortcut (Cmd+Shift+V)
- Auto-pasting into the previously active application via Accessibility APIs
- Preferences to control history retention limits

## Run & Build

To compile the application into a standalone `.app` bundle:

```bash
cd /Users/sashornock/Documents/Scripts/ScriptProductioin/BoarderPatrol
./build_app.sh
```

To run the application, simply open the resulting `dist/BoarderPatrol.app`.

## Project Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/APP_ROADMAP.md](docs/APP_ROADMAP.md)
- [docs/WORK_LOG.md](docs/WORK_LOG.md)

## Launchers

- `build_app.sh`: compiles the `.swift` sources into the macOS `.app` bundle.
