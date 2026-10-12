import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var clipboardMonitor = ClipboardMonitor()
    /// Last non-ClipMonster frontmost app (for restoring focus after copy).
    var lastFrontmostApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshStatusItem()
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
        }

        let contentView = ContentView(monitor: clipboardMonitor, appDelegate: self)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 540)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        registerHotKeys()
        DragTempCleanup.run()
        #if !MAS
        TerminalPasteTap.install(monitor: clipboardMonitor)
        #endif

        NotificationCenter.default.addObserver(forName: NSNotification.Name("ShortcutChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKeys()
        }
        NotificationCenter.default.addObserver(forName: .clipMonsterShortcutRecordingBegan, object: nil, queue: .main) { _ in
            CarbonHotKeyCenter.shared.unregisterAll()
        }
        NotificationCenter.default.addObserver(forName: .clipMonsterShortcutRecordingEnded, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKeys()
        }
        NotificationCenter.default.addObserver(forName: .clipMonsterCapturePauseChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshStatusItem()
        }

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

        WelcomeWindowController.showIfNeeded { [weak self] in
            self?.togglePopover(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CarbonHotKeyCenter.shared.unregisterAll()
        clipboardMonitor.prepareForTermination()
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        button.image = Self.menuBarArtwork() ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipMonster")
        button.image?.isTemplate = false
        button.appearsDisabled = clipboardMonitor.capturePaused
        if clipboardMonitor.capturePaused {
            button.toolTip = "ClipMonster 2.0 — capture paused"
        } else {
            button.toolTip = "ClipMonster 2.0"
        }
    }

    private static func menuBarArtwork() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "Clipmonster", withExtension: "jpg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    func registerHotKeys() {
        let popoverStatus = CarbonHotKeyCenter.shared.register(
            id: CarbonHotKeyCenter.popoverID,
            shortcut: clipboardMonitor.globalShortcut,
            exclusive: false
        ) { [weak self] in
            self?.togglePopover(nil)
        }
        if popoverStatus != noErr {
            clipboardMonitor.globalShortcutError = "Could not reserve \(clipboardMonitor.globalShortcut.displayString). Choose another shortcut."
        } else {
            clipboardMonitor.globalShortcutError = nil
        }

        let pathStatus = CarbonHotKeyCenter.shared.register(
            id: CarbonHotKeyCenter.pathPasteID,
            shortcut: clipboardMonitor.pathPasteShortcut,
            exclusive: true
        ) { [weak self] in
            self?.pasteLatestImagePathIntoFrontmostApp()
        }
        if pathStatus == noErr {
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
                if let front = NSWorkspace.shared.frontmostApplication,
                   front.bundleIdentifier != Bundle.main.bundleIdentifier {
                    lastFrontmostApp = front
                }
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    var lastFrontmostIsTerminal: Bool { FrontApp.isTerminal(lastFrontmostApp) }

    /// Restore the previous app after a copy. Direct builds can also type ⌘V.
    func autoPasteIntoPreviousApp() {
        popover.performClose(nil)
        let target = lastFrontmostApp
        focus(target)
        #if !MAS
        guard Distribution.supportsAutoPaste else { return }
        if FrontApp.isTerminal(target) {
            Self.pasteCommandVIntoTerminal()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                Self.simulateCommandV()
            }
        }
        #endif
    }

    /// Copy the newest captured image's path. Direct builds paste it into the
    /// focused app; the Store edition leaves it on the clipboard.
    func pasteLatestImagePathIntoFrontmostApp() {
        let front = NSWorkspace.shared.frontmostApplication
        let terminal = FrontApp.isTerminal(front)
        guard clipboardMonitor.copyLatestImagePathToClipboard(shellQuoted: terminal) else { return }
        #if !MAS
        guard Distribution.supportsAutoPaste else { return }
        if terminal {
            Self.pasteCommandVIntoTerminal()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                Self.simulateCommandV()
            }
        }
        #endif
    }

    /// Close the popover and give focus back so the user can press ⌘V.
    func handFocusBackAfterCopy() {
        popover.performClose(nil)
        focus(lastFrontmostApp)
    }

    /// Terminal ignores a plain `activate()` from a menu-bar app, so ⌘V never
    /// reaches it. Yield first, then ask Terminal to take activation from us.
    private func focus(_ app: NSRunningApplication?) {
        guard let app else { return }
        if FrontApp.isTerminal(app) {
            NSApp.yieldActivation(to: app)
            _ = app.activate(from: .current, options: [])
        } else {
            app.activate()
        }
    }

    #if !MAS
    /// Terminal ignores a ⌘V posted on the HID tap, and it ignores one that
    /// arrives while the path shortcut's modifiers are still held. Wait those
    /// out, then post ⌘V on the session tap with the left-command flag set.
    static func pasteCommandVIntoTerminal() {
        func tick(focusWaits: Int, modifierWaits: Int) {
            let focused = FrontApp.isTerminal(NSWorkspace.shared.frontmostApplication)
            let mods = CGEventSource.flagsState(.hidSystemState)
            let held = !mods.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).isEmpty
            if (focused || focusWaits >= 15) && (!held || modifierWaits >= 20) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    insertClipboardTextIntoTerminal()
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                tick(
                    focusWaits: focusWaits + (focused ? 0 : 1),
                    modifierWaits: modifierWaits + (held ? 1 : 0)
                )
            }
        }
        tick(focusWaits: 0, modifierWaits: 0)
    }

    static func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Session-tap ⌘V with the left-command device flag. Terminal drops the
    /// HID-tap event that other apps accept.
    static func insertClipboardTextIntoTerminal() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              FrontApp.isTerminal(app) else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
    #endif
}

/// Apps that cannot insert an image from the pasteboard. A screenshot has to
/// arrive as a filesystem path or the paste looks like it did nothing.
enum FrontApp {
    static func isTerminal(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if app.bundleIdentifier == "com.apple.Terminal" { return true }
        return app.localizedName == "Terminal"
    }
}

extension Notification.Name {
    static let clipMonsterClosePopover = Notification.Name("ClipMonsterClosePopover")
    static let clipMonsterShortcutRecordingBegan = Notification.Name("ClipMonsterShortcutRecordingBegan")
    static let clipMonsterShortcutRecordingEnded = Notification.Name("ClipMonsterShortcutRecordingEnded")
    static let clipMonsterCapturePauseChanged = Notification.Name("ClipMonsterCapturePauseChanged")
}
