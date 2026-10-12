import Cocoa

#if !MAS
/// Terminal's Edit > Paste is Command-V, and it inserts nothing when the
/// clipboard is only a screenshot. Control-V is not paste in Terminal at all
/// (the shell treats it as "insert the next character literally").
///
/// While Terminal is focused, both of those chords on an image clipboard are
/// turned into a paste of the PNG's file path.
enum TerminalPasteTap {
    private static weak var monitor: ClipboardMonitor?
    private static var tap: CFMachPort?
    private static var prompted = false

    static func install(monitor: ClipboardMonitor) {
        self.monitor = monitor
        guard Distribution.supportsAutoPaste else { return }
        promptIfNeeded()
        installTap()
        guard tap == nil else { return }
        var tries = 0
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { timer in
            tries += 1
            promptIfNeeded()
            installTap()
            if tap != nil || tries >= 40 {
                timer.invalidate()
            }
        }
    }

    private static func promptIfNeeded() {
        guard !AXIsProcessTrusted(), !prompted else { return }
        prompted = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func installTap() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: terminalPasteTapCallback,
            userInfo: nil
        ) else { return }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private static func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let monitor, FrontApp.isTerminal(NSWorkspace.shared.frontmostApplication) else {
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == 9 else {
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let commandV = command && !control && !option && !shift
        let controlV = control && !command && !option && !shift
        guard commandV || controlV else { return Unmanaged.passUnretained(event) }
        guard monitor.replaceCurrentImageWithShellPath() else {
            return Unmanaged.passUnretained(event)
        }
        // Command-V continues into Terminal, which now pastes the path.
        // Control-V would not paste, so drop it and send Command-V once Control is up.
        if controlV {
            AppDelegate.pasteCommandVIntoTerminal()
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    fileprivate static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        return handle(event)
    }
}

private func terminalPasteTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    TerminalPasteTap.handle(type: type, event: event)
}
#endif
