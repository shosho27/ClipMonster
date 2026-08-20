import Cocoa
import SwiftUI
import Carbon

/// Registers an exclusive system hotkey, which prevents the focused app from
/// receiving the keystroke before ClipMonster has prepared the image path.
final class PathPasteHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var action: () -> Void
    
    init(action: @escaping () -> Void) {
        self.action = action
    }
    
    @discardableResult
    func register(shortcut: CustomShortcut) -> OSStatus {
        unregister()
        
        if handlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                Self.eventHandler,
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef
            )
            guard status == noErr else { return status }
        }
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x434D5048), id: 1) // "CMPH"
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(for: shortcut),
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )
        if status != noErr { hotKeyRef = nil }
        return status
    }
    
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
    
    private static let eventHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<PathPasteHotKey>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async { manager.action() }
        return noErr
    }
    
    private static func carbonModifiers(for shortcut: CustomShortcut) -> UInt32 {
        let modifiers = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var clipboardMonitor = ClipboardMonitor()
    var globalMonitor: Any?
    var localMonitor: Any?
    private lazy var pathPasteHotKey = PathPasteHotKey { [weak self] in
        self?.pasteLatestImagePathIntoFrontmostApp()
    }
    /// Last non-ClipMonster frontmost app (for auto-paste).
    var lastFrontmostApp: NSRunningApplication?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarArtwork() ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipMonster 2.0")
            button.image?.isTemplate = false
            button.toolTip = "ClipMonster 2.0"
            button.action = #selector(togglePopover(_:))
        }
        
        let contentView = ContentView(monitor: clipboardMonitor, appDelegate: self)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 540)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        setupShortcutMonitors(shortcut: clipboardMonitor.globalShortcut)
        registerPathPasteHotKey()
        DragTempCleanup.run()
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ShortcutChanged"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.setupShortcutMonitors(shortcut: self.clipboardMonitor.globalShortcut)
            self.registerPathPasteHotKey()
        }
        
        // Track previous app for auto-paste
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.lastFrontmostApp = app
            }
        }
        
        // Keep the transient popover open for the duration of an external drag
        NotificationCenter.default.addObserver(forName: DragSession.began, object: nil, queue: .main) { [weak self] _ in
            self?.popover.behavior = .applicationDefined
        }
        NotificationCenter.default.addObserver(forName: DragSession.ended, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.popover.behavior = .transient
            if self.popover.isShown {
                self.popover.performClose(nil)
            }
        }
        
        NotificationCenter.default.addObserver(forName: .clipMonsterClosePopover, object: nil, queue: .main) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    private static func menuBarArtwork() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "Clipmonster", withExtension: "jpg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }
    
    func setupShortcutMonitors(shortcut: CustomShortcut) {
        if let currentMonitor = globalMonitor {
            NSEvent.removeMonitor(currentMonitor)
            globalMonitor = nil
        }
        if let currentMonitor = localMonitor {
            NSEvent.removeMonitor(currentMonitor)
            localMonitor = nil
        }
        
        let handler: (NSEvent) -> Void = { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.rawValue == shortcut.modifiers && event.keyCode == shortcut.keyCode {
                DispatchQueue.main.async { self?.togglePopover(nil) }
            }
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
        }
        // Local monitor so the shortcut also works when ClipMonster is frontmost
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.rawValue == shortcut.modifiers && event.keyCode == shortcut.keyCode {
                DispatchQueue.main.async { self.togglePopover(nil) }
                return nil
            }
            return event
        }
    }

    private func registerPathPasteHotKey() {
        let status = pathPasteHotKey.register(shortcut: clipboardMonitor.pathPasteShortcut)
        if status == noErr {
            clipboardMonitor.pathPasteShortcutError = nil
        } else {
            clipboardMonitor.pathPasteShortcutError = "Could not reserve \(clipboardMonitor.pathPasteShortcut.displayString). Choose another shortcut."
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                // Snapshot previous app before we take focus
                if let front = NSWorkspace.shared.frontmostApplication,
                   front.bundleIdentifier != Bundle.main.bundleIdentifier {
                    lastFrontmostApp = front
                }
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    /// Copy is already done; restore previous app and simulate Cmd+V.
    func autoPasteIntoPreviousApp() {
        popover.performClose(nil)
        let target = lastFrontmostApp
        target?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.simulateCommandV()
        }
    }

    /// Copy the newest captured image's path, then paste it into whichever app
    /// is currently focused (such as Terminal) without opening ClipMonster.
    func pasteLatestImagePathIntoFrontmostApp() {
        guard clipboardMonitor.copyLatestImagePathToClipboard() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Self.simulateCommandV()
        }
    }
    
    static func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

extension Notification.Name {
    static let clipMonsterClosePopover = Notification.Name("ClipMonsterClosePopover")
}
