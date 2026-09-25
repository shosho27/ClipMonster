import Cocoa
import SwiftUI

// MARK: - UI Views

struct ShortcutRecorder: View {
    @Binding var shortcut: CustomShortcut
    @State private var isRecording = false
    @State private var localMonitor: Any?
    
    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                isRecording = true
                startRecording()
            }
        }) {
            Text(isRecording ? "Type Shortcut..." : shortcut.displayString)
                .frame(minWidth: 80)
        }
        .onDisappear { stopRecording() }
    }
    
    func startRecording() {
        NotificationCenter.default.post(name: .clipMonsterShortcutRecordingBegan, object: nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierKeyCodes.contains(event.keyCode) {
                return event
            }
            
            let char = event.charactersIgnoringModifiers ?? ""
            let newShortcut = CustomShortcut(keyCode: event.keyCode, modifiers: mods.rawValue, keyString: char.uppercased())
            
            DispatchQueue.main.async {
                self.shortcut = newShortcut
                self.stopRecording()
            }
            return nil
        }
    }
    
    func stopRecording() {
        let wasRecording = isRecording
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if wasRecording {
            NotificationCenter.default.post(name: .clipMonsterShortcutRecordingEnded, object: nil)
        }
    }
}

/// Bridges popover key handling without capturing stale SwiftUI struct state.
final class HistoryKeyHandler: ObservableObject {
    var showPreferences: () -> Bool = { false }
    var searchText: () -> String = { "" }
    var setSearchText: (String) -> Void = { _ in }
    var focusedIndex: () -> Int = { 0 }
    var setFocusedIndex: (Int) -> Void = { _ in }
    var filtered: () -> [ClipboardItem] = { [] }
    var activate: (ClipboardItem) -> Void = { _ in }
    /// Space — large in-app preview for images, or open file items.
    var previewFocused: (ClipboardItem) -> Void = { _ in }
    /// True when the large image overlay is visible (Esc dismisses it first).
    var isLargePreviewVisible: () -> Bool = { false }
    var dismissLargePreview: () -> Void = { }
    private var monitor: Any?
    
    func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.showPreferences() { return event }
            
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
                if event.keyCode == 53 {
                    self.setSearchText("")
                    NotificationCenter.default.post(name: .clipMonsterClosePopover, object: nil)
                    return nil
                }
                return event
            }
            return self.handle(event)
        }
    }
    
    func remove() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
    
    private func handle(_ event: NSEvent) -> NSEvent? {
        let items = filtered()
        let idx = focusedIndex()
        
        switch event.keyCode {
        case 53: // Escape
            if isLargePreviewVisible() {
                dismissLargePreview()
                return nil
            }
            NotificationCenter.default.post(name: .clipMonsterClosePopover, object: nil)
            return nil
        case 125:
            if !items.isEmpty { setFocusedIndex(min(idx + 1, items.count - 1)) }
            return nil
        case 126:
            if !items.isEmpty { setFocusedIndex(max(idx - 1, 0)) }
            return nil
        case 36, 76:
            if items.indices.contains(idx) { activate(items[idx]) }
            return nil
        case 49: // Space
            if items.indices.contains(idx) { previewFocused(items[idx]) }
            return nil
        case 18, 19, 20, 21, 23, 22, 26, 28, 25:
            let map: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
            if let n = map[event.keyCode], items.indices.contains(n) {
                setFocusedIndex(n)
                activate(items[n])
                return nil
            }
            return event
        default:
            return event
        }
    }
    
    deinit { remove() }
}

