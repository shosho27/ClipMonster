import Cocoa
import Carbon

@main
enum CapturePageTargetTests {
    @MainActor static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 30, y: 30, width: 1100, height: 820)
        let viewport = CGRect(x: 250, y: 150, width: 880, height: 700)
        let document = CGRect(x: 250, y: 150, width: 880, height: 5000)
        let page = CapturePageTarget.Region(role: "AXWebArea", frame: document)
        let scroll = CapturePageTarget.Region(role: kAXScrollAreaRole, frame: viewport)
        let point = CGPoint(x: 400, y: 400)
        precondition(CapturePageTarget.visibleFrame(ancestors: [page, scroll], window: window, screens: [screen], point: point) == viewport)
        let nested = CGRect(x: 300, y: 300, width: 400, height: 350)
        precondition(CapturePageTarget.visibleFrame(ancestors: [.init(role: kAXScrollAreaRole, frame: nested), page, scroll],
                      window: window, screens: [screen], point: point) == nested)
        // A document's full height must never become the screenshot viewport.
        precondition(CapturePageTarget.visibleFrame(ancestors: [page], window: window, screens: [screen], point: point) == viewport)
        precondition(CapturePageTarget.visibleFrame(ancestors: [scroll], window: window, screens: [screen], point: CGPoint(x: 100, y: 70)) == nil)
        let leftScreen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let leftViewport = viewport.offsetBy(dx: -1440, dy: 0)
        precondition(CapturePageTarget.visibleFrame(ancestors: [.init(role: kAXScrollAreaRole, frame: leftViewport)],
                      window: window.offsetBy(dx: -1440, dy: 0), screens: [screen, leftScreen],
                      point: CGPoint(x: -1000, y: 400)) == leftViewport)
        let clipboardCount = NSPasteboard.general.changeCount
        _ = NSApplication.shared
        var escapeCalls = 0
        let escape = CaptureEscapeHotKey(action: { escapeCalls += 1 })
        escape.register()
        precondition(escape.isRegistered, "Could not reserve Escape")
        func deliverHotKey(signature: OSType) {
            var event: EventRef?
            precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr)
            var id = EventHotKeyID(signature: signature, id: 1)
            precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           MemoryLayout<EventHotKeyID>.size, &id) == noErr)
            _ = SendEventToEventTarget(event, GetApplicationEventTarget())
            ReleaseEvent(event)
        }
        deliverHotKey(signature: OSType(0x434D5048))
        precondition(escapeCalls == 0, "Another shortcut incorrectly cancelled capture")
        deliverHotKey(signature: OSType(0x53434553))
        precondition(escapeCalls == 1, "Escape hotkey did not call cancellation")
        escape.unregister()
        precondition(!escape.isRegistered)
        if AXIsProcessTrusted() && CGPreflightScreenCaptureAccess() {
            let capture = ScrollingCapture()
            for _ in 0..<3 {
                capture.start(target: nil) { _ in preconditionFailure("Choosing a page must not save an image") }
                precondition(capture.isRunning && capture.isChoosingPage)
                capture.cancel()
                precondition(!capture.isRunning && !capture.isChoosingPage)
                precondition(NSApp.windows.allSatisfy { !$0.isVisible }, "Cancel left a visible capture window")
            }
            precondition(NSPasteboard.general.changeCount == clipboardCount, "Cancel changed the clipboard")
            print("PASS: Escape hotkey registration, repeated arm/cancel removes controls and preserves the clipboard")
        } else {
            print("SKIP: native arm/cancel lifecycle requires existing Accessibility and Screen Recording grants")
        }
        print("PASS: viewport clipping, nested scrollers, toolbar rejection, document-height fallback, and secondary displays")
        if CommandLine.arguments.contains("--chrome-at-pointer") {
            guard let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }),
                  let point = CGEvent(source: nil)?.location else { preconditionFailure("Open Chrome with the pointer inside page content") }
            let top = NSScreen.screens.first!.frame.maxY
            let displays = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
            let viewport = CapturePageTarget.resolve(point: point, pid: chrome.processIdentifier, screens: displays)
            precondition(viewport != nil, "Chrome page click was rejected")
            precondition(viewport!.contains(point))
            print("PASS: real Chrome page hit testing at the pointer")
        }
    }
}
