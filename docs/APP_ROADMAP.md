# App Roadmap: ClipMonster 2.0

## Working boundary

This is the independent 2.0 working copy. The original ClipMonster remains unchanged in `../ClipMonster/` while markup work is developed here.

## Phase 1: MVP — done

- [x] Project dirs (`src`, `dist`, `docs`)
- [x] `build_app.sh` → `ClipMonster 2.0.app`
- [x] `NSStatusItem` + `NSPopover`
- [x] `ClipboardMonitor` for text history
- [x] SwiftUI history list

## Phase 2: Rich media — done

- [x] Images (`NSImage`) in monitor + UI thumbnails
- [x] File URL items
- [x] Drag-out (file URL for Terminal/Finder; PNG data for image apps)
- [x] Auto-paste via Accessibility / simulated Cmd+V (preference toggle)
- [x] Accessibility Settings deep-link

## Phase 3: Shortcut & preferences — done

- [x] Global hotkey (customizable; 2.0 default Control-Option-V)
- [x] Clear / purge history
- [x] History limit preference
- [x] Customizable global shortcut in Preferences
- [x] Optional disk persistence + custom storage path
- [x] Unlimited-history preference
- [x] Start at login (Login Items / LaunchAgent fallback)
- [x] Multi-select copy (Shift-click)
- [x] Scrollable preferences + pinned header/footer (Quit always reachable)

## Phase 4: Core upgrades — done

| # | Upgrade | Status |
|---|---------|--------|
| 1 | Auto-paste on select into previous app | Done |
| 2 | Search / filter history | Done |
| 3 | Keyboard navigation (↑/↓, Return, Esc, 1–9) | Done |
| 4 | Image de-dupe (content hash) | Done |
| 5 | Cleaner drag filenames for Terminal | Done |
| 6 | OCR (Vision) — on-demand + optional auto + searchable | Done |
| 7 | Local + global shortcut monitors | Done |
| 8 | Clean up drag temp PNGs on launch | Done |
| 9 | Large in-app image preview (thumb / eye / Space) | Done |
| 10 | Double-click / button → open in Preview.app | Done |
| 11 | Reveal captured image in Finder | Done |
| 12 | Copy/paste latest image path into a CLI | Done |

## Phase 5: Next ideas

- [x] Screen-capture markup editor: Select, pen, arrow, box, text, color, width, undo/clear, and annotated-copy save
- [x] Annotation selection: move, corner resize, rotation handle, arrow endpoints, inspector color/scale/rotation/delete, editable text
- [ ] Pin favorite items
- [ ] Optional: keep popover open after drag
- [ ] Save image as…
- [ ] Exclude apps from capture
- [ ] Rich text / RTF history type
- [ ] Code signing / notarization for smoother Login Items + distribution
