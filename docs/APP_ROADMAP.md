# App Roadmap: ClipMonster 2.0

## Working boundary

This is the independent 2.0 working copy. The original ClipMonster remains unchanged in `../ClipMonster/` while markup and Store packaging are developed here.

## Phase 1: MVP — done

- [x] Project dirs (`src`, `dist`, `docs`)
- [x] `build_app.sh` → `ClipMonster 2.0.app`
- [x] `NSStatusItem` + `NSPopover`
- [x] `ClipboardMonitor` for text history
- [x] SwiftUI history list

## Phase 2: Rich media — done

- [x] Images in monitor + UI thumbnails (disk-backed PNG + 128px downsample)
- [x] File URL items
- [x] Drag-out (file URL for Terminal/Finder; PNG data for image apps)
- [x] Auto-paste via Accessibility / simulated Cmd+V (Direct edition preference)
- [x] Accessibility Settings deep-link (Direct edition)

## Phase 3: Shortcut & preferences — done

- [x] Global hotkey (customizable; 2.0 default Control-Option-V)
- [x] Clear / purge history
- [x] History limit preference
- [x] Customizable global shortcut in Preferences
- [x] Optional disk persistence + custom storage path
- [x] Unlimited-history preference
- [x] Start at login (`SMAppService`; LaunchAgent fallback in Direct only)
- [x] Multi-select copy (Shift-click)
- [x] Scrollable preferences + pinned header/footer (Quit always reachable)

## Phase 4: Core upgrades — done

| # | Upgrade | Status |
|---|---------|--------|
| 1 | Auto-paste on select into previous app (Direct) | Done |
| 2 | Search / filter history | Done |
| 3 | Keyboard navigation (↑/↓, Return, Esc, 1–9) | Done |
| 4 | Image de-dupe (SHA-256 of PNG file bytes) | Done |
| 5 | Cleaner drag filenames for Terminal | Done |
| 6 | OCR (Vision) — on-demand + optional auto + searchable | Done |
| 7 | Global shortcut (NSEvent monitors, later replaced by Carbon) | Done |
| 8 | Clean up drag temp PNGs on launch | Done |
| 9 | Large in-app image preview (thumb / eye / Space) | Done |
| 10 | Double-click / button → open in Preview.app | Done |
| 11 | Reveal captured image in Finder | Done |
| 12 | Latest image path onto the clipboard / into a CLI | Done |

## Phase 5: Markup, memory, Store cut

Shipped in this working copy:

- [x] Screen-capture markup editor: Select, pen, arrow, box, text, color, width, undo/clear, and annotated-copy save
- [x] Annotation selection: move, corner resize, rotation handle, arrow endpoints, inspector color/scale/rotation/delete, editable text
- [x] Disk-backed captures: thumbnails in RAM, full PNG loaded only for preview/markup/OCR/copy/drag
- [x] Xcode project + App Sandbox entitlements + `MAS` compile flag
- [x] Carbon hotkeys (Accessibility not required for the shortcut)
- [x] Store edition: no `CGEvent` paste, no LaunchAgent writes
- [x] Security-scoped bookmarks for custom storage and file clips
- [x] First-launch welcome window for the menu-bar-only app
- [x] Pause capture, purge confirmation, in-app privacy policy
- [x] Concealed / transient / auto-generated pasteboard skip + known password managers

Still open:

- [ ] Pin favorite items
- [ ] Optional: keep popover open after drag
- [ ] Save image as…
- [ ] Exclude-app picker in Preferences (password managers are already skipped)
- [ ] Rich text / RTF history type

## Phase 6: Sell and distribute (do at home)

The Store-shaped binary is in this tree. **Do not archive or upload from the current machine.** It only has a free Personal Team (`Apple Development: shane.shornock@gmail.com`, team `5V68L429TM`). The paid Apple Developer Program is on the **home Apple Developer account**. Next implementation pass is on the home Mac, signed into that account.

Submit the **ClipMonster-MAS** scheme (MacAppStore, `-D MAS`, sandbox). The Direct `./build_app.sh` binary that runs day-to-day will fail review (synthetic ⌘V, no App Sandbox).

At home:

1. Open this folder, pull if the working copy is on git, quit any running ClipMonster 2.0.
2. Sign Xcode / App Store Connect into the home Developer Program team. Confirm an **Apple Distribution** certificate (Mac App Store) and, for the Direct edition later, a **Developer ID Application** certificate.
3. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and `sudo xcodebuild -license` if needed.
4. Open `ClipMonster.xcodeproj`, select scheme **ClipMonster-MAS**, set the target team to the home team (replace `DEVELOPMENT_TEAM = 5V68L429TM` in `Config/Common.xcconfig` if Xcode does not override it).
5. Archive → Organizer → Distribute App → App Store Connect. Keep bundle ID `com.sashornock.ClipMonster2` unless you are intentionally creating a new listing.
6. Host `docs/PRIVACY.md` at a stable HTTPS URL; paste it into App Store Connect App Information and leave the in-app Privacy Policy button as-is.
7. App Store Connect: nutrition labels (clipboard history stored on device, not linked, no tracking), age rating, export compliance (uses non-exempt encryption: **No**), category Productivity.
8. Listing: replace `Resources/AppStoreIcon.png` with a true 1024 asset on Apple’s icon grid; 16:10 screenshots (2880×1800) of the real MAS binary (copy-then-⌘V, no auto-paste); subtitle; keywords; review notes that this is a **menu bar app with no Dock icon** and that the first-launch window explains that.
9. TestFlight the MAS archive, then submit.

Checklist:

- [ ] Home Developer Program team selected in Xcode (not the free Personal Team on this laptop)
- [ ] Apple Distribution certificate + Mac App Store provisioning profile
- [ ] Xcode license + `xcode-select` pointed at Xcode.app
- [ ] Host `docs/PRIVACY.md` HTTPS URL in App Store Connect
- [ ] App record, nutrition labels, age rating, export compliance
- [ ] 1024 icon on the Apple grid (current PNG is an upscale from 960px)
- [ ] 16:10 screenshots of the MAS build, review notes (menu bar, no Dock icon)
- [ ] TestFlight on the **ClipMonster-MAS** archive, then submit
- [ ] Developer ID signing + notarization for the Direct edition (separate from MAS)

Product leftovers (not required for first upload): pin favorites, keep popover after drag, save image as, exclude-app picker, rich text.
