# Work Log: ClipMonster

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
- Documentation refresh + push to GitHub  

## Earlier (pre-log)

- Menu bar clipboard history (text, images, files)
- Global shortcut + recorder
- Disk persistence + purge
- Multi-select copy
- Sensitive pasteboard skip
- Initial repo: `github.com/shosho27/ClipMonster`
