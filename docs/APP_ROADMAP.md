# App Roadmap: BoarderPatrol

## Phase 1: MVP (Minimum Viable Product)
- [ ] Scaffold the project directories (`src`, `dist`, `docs`).
- [ ] Write the `build_app.sh` script to compile Swift files into a `.app` bundle.
- [ ] Create the `NSStatusItem` and a basic empty `NSPopover`.
- [ ] Implement `ClipboardMonitor` to poll for plain text changes and store them in memory.
- [ ] Build the SwiftUI list to display the copied strings.

## Phase 2: Rich Media & Auto-Paste
- [ ] Upgrade `ClipboardMonitor` to support Images (`NSImage`), Rich Text, and Files.
- [ ] Implement UI elements for displaying image thumbnails and file paths.
- [ ] Write the Accessibility Event logic to simulate `Cmd+V` on item selection (Auto-paste).
- [ ] Request and handle Accessibility permissions from macOS.

## Phase 3: Global Shortcut & Preferences
- [ ] Implement global hotkey registration (Cmd+Shift+V).
- [ ] Add a "Clear History" button in the UI.
- [ ] Build a Preferences pane to configure memory limits (e.g., maximum of 50 items).
- [ ] (Stretch) Allow users to change the global hotkey via the UI.
