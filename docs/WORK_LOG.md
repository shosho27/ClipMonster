# Work Log: ClipMonster

## 2026-07-23

### Unlimited capture storage & Finder reveal
- Added **Keep unlimited history** in Preferences; retention is then constrained only by available memory/disk until the user deletes or purges items.
- Storage-folder changes now validate write access, copy the current persisted history to the chosen directory, and remove only ClipMonster-owned files from the old location.
- Added an image-row **folder** button to reveal the image PNG in Finder; temporary PNGs are created only when persistence is off.

### CLI image-path handoff
- Added an image-row **Copy Path** button.
- Added a configurable global **Paste latest image path** shortcut, default **Command–Shift–V**. It resolves a screenshot directly from the current pasteboard when needed, then pastes its PNG path into the focused CLI.
- Replaced the initial observer-based shortcut with an exclusive system hotkey so Terminal cannot paste the prior clipboard text before ClipMonster handles the command.

### Image preview & Preview.app
- Larger list thumbnails (56×56).
- In-popover **large preview overlay** (thumb click, eye button, Space).
- **Double-click** image (or ↗ button) → open PNG in **Preview.app** via `NSWorkspace`.
- Esc dismisses overlay before closing the popover.
- File rows: double-click / Space opens the file.

## 2026-07-21

### Preferences layout fix
- Settings content overflowed the fixed-height popover; Quit was unreachable.
- Preferences wrapped in `ScrollView`; header (Done + gear) and footer (Quit) pinned.
- Slightly larger popover (360×540).

### Core upgrades batch
1. Auto-paste on select (previous app + CGEvent ⌘V)  
2. Search / filter (includes OCR text)  
3. Keyboard navigation (↑/↓, Return, Esc, 1–9)  
4. Image de-dupe (SHA-256 of PNG bytes) + cleaner drag names (`clipboard-yyyy-MM-dd-HHmmss.png`)  
5. **OCR** via Apple Vision — on-demand button, optional auto-OCR, searchable + persisted  
6. Local + global shortcut monitors  
7. Temp PNG cleanup on launch (>24h)  

### Earlier same day
- Drag-out from history; Terminal-friendly file URL drag  
- Start at login (`SMAppService` / LaunchAgent fallback)  
- Docs renamed/aligned from legacy “BoarderPatrol” to **ClipMonster**  
- Documentation refresh + push to GitHub (`135f5f3`)  
- Docs re-synced for preview features (local; push when ready)

## Earlier (pre-log)

- Menu bar clipboard history (text, images, files)
- Global shortcut + recorder
- Disk persistence + purge
- Multi-select copy
- Sensitive pasteboard skip
- Initial repo: `github.com/shosho27/ClipMonster`
