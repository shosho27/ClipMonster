# Architecture: BoarderPatrol

## Overview
BoarderPatrol is built as a single-file (or minimal multi-file) Swift application leveraging `AppKit` and `SwiftUI`. 

## Core Components

1. **AppDelegate (AppKit)**
   - Configures the app to run as an `LSUIElement` (Accessory app), hiding the Dock icon.
   - Manages the `NSStatusItem` (the Menu Bar icon).
   - Handles the presentation of the `NSPopover` containing the SwiftUI views.

2. **ClipboardMonitor (ObservableObject)**
   - Sets up a repeating `Timer` to poll the `NSPasteboard.general.changeCount`.
   - When a change is detected, it reads the pasteboard for `String`, `NSImage`, `URL`, or `NSAttributedString`.
   - Maintains an in-memory array of the recent items.
   - Handles the logic for setting the clipboard back to a historical item.

3. **Auto-Paste Mechanism**
   - Utilizes `CGEvent` and macOS Accessibility APIs to programmatically simulate a `Cmd+V` keystroke immediately after the user selects a historical item, injecting the content into the previously focused application.

4. **Global Shortcut Manager**
   - Registers a global hotkey (e.g., Cmd+Shift+V) using `NSEvent.addGlobalMonitorForEvents` or Carbon Event APIs, triggering the `NSPopover` to appear regardless of the active application.

5. **ContentView (SwiftUI)**
   - Renders the history list.
   - Truncates long text strings.
   - Displays thumbnails for images.
   - Provides a settings/preferences tab to control retention limits.

## Build System
- Compiled directly using `swiftc` via the `build_app.sh` script.
- The script manually constructs the `BoarderPatrol.app` directory structure, generates the `Info.plist`, and places the compiled executable in `Contents/MacOS/`.
