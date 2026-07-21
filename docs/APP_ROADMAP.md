# App Roadmap: ClipMonster

## Phase 1: MVP — done

- [x] Project dirs (`src`, `dist`, `docs`)
- [x] `build_app.sh` → `ClipMonster.app`
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

- [x] Global hotkey (customizable; default Fn+V)
- [x] Clear / purge history
- [x] History limit preference
- [x] Customizable global shortcut in Preferences
- [x] Optional disk persistence + custom storage path
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

## Phase 5: Next ideas

- [ ] Pin favorite items
- [ ] Full-size image preview (hover / Space)
- [ ] Optional: keep popover open after drag
- [ ] “Copy path” / “Reveal in Finder” for file & image items
- [ ] Save image as…
- [ ] Exclude apps from capture
- [ ] Rich text / RTF history type
- [ ] Code signing / notarization for smoother Login Items + distribution
