import Cocoa
import SwiftUI
import ImageIO

@MainActor
final class ScrollingCapture: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    private var task: Task<Void, Never>?
    private var selectionWindows: [NSWindow] = []
    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private var targetApp: NSRunningApplication?
    private var originalPointer: CGPoint?
    private var stopRequested = false
    private var onSaved: ((NSImage) -> Bool)?

    func start(target: NSRunningApplication?, onSaved: @escaping (NSImage) -> Bool) {
        guard !isRunning else { return }
        guard let target, !target.isTerminated,
              target.bundleIdentifier != Bundle.main.bundleIdentifier else {
            alert("Open your webpage first", "Bring your browser to the front, then open ClipMonster and click Scrolling Capture.")
            return
        }
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            alert("Accessibility permission needed", "Enable ClipMonster 2.0 in System Settings → Privacy & Security → Accessibility, then try again.")
            return
        }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            alert("Screen Recording permission needed", "Enable ClipMonster 2.0 in System Settings → Privacy & Security → Screen & System Audio Recording. You may need to quit and reopen the app.")
            return
        }
        let instructions = NSAlert()
        instructions.messageText = "Capture a scrolling webpage"
        instructions.informativeText = "Start at the top of your webpage. Drag a rectangle around the scrolling content, excluding browser toolbars, fixed headers, and scrollbars. Keep the browser visible and leave the mouse alone during capture.\n\nClipMonster captures from the current position to where scrolling stops. Stop & Save keeps what was captured; Escape cancels."
        instructions.addButton(withTitle: "Select Webpage Area")
        instructions.addButton(withTitle: "Cancel")
        guard instructions.runModal() == .alertFirstButtonReturn else { return }
        targetApp = target
        self.onSaved = onSaved
        originalPointer = CGEvent(source: nil)?.location
        stopRequested = false
        isRunning = true
        status = "Select the scrolling content · Escape cancels"
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.cancel() }
                return nil
            }
            return event
        }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.cancel() } }
        }
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = CaptureSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.selected = { [weak self] localRect in
                let globalRect = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                DispatchQueue.main.async { self?.beginCapture(rect: globalRect) }
            }
            window.contentView = view
            window.orderFrontRegardless()
            selectionWindows.append(window)
        }
    }

    func stopAndSave() { stopRequested = true; status = "Saving capture…" }

    func cancel() {
        task?.cancel()
        if task == nil { finish() }
    }

    private func beginCapture(rect: CGRect) {
        guard isRunning, task == nil else { return }
        guard rect.width >= 200, rect.height >= 150 else {
            status = "Select an area at least 200 × 150 points"
            return
        }
        for window in selectionWindows { window.orderOut(nil) }
        selectionWindows.removeAll()
        // AppKit uses bottom-left coordinates; Quartz capture and events use top-left.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let captureRect = CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height).integral
        targetApp?.activate(options: [])
        let control = NSPanel(contentRect: CGRect(x: rect.minX, y: rect.maxY - 90, width: 310, height: 85),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        control.level = .floating
        control.isFloatingPanel = true
        control.hidesOnDeactivate = false
        control.contentView = NSHostingView(rootView: ScrollCaptureControls(capture: self))
        panel = control
        task = Task { [weak self] in
            guard let self else { return }
            defer { finish() }
            do {
                try await pause(700)
                let previous = try await screenshot(captureRect)
                guard var pixels = ScrollCaptureStitcher.Pixels(previous) else { throw CaptureError("Could not read the captured pixels.") }
                var strips = [previous]
                var totalHeight = previous.height
                var unchanged = 0
                var warning: String?
                let started = Date()
                while !stopRequested {
                    try Task.checkCancellation()
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp?.processIdentifier else {
                        throw CaptureError("The browser lost focus. The capture was cancelled so another app would not be captured or scrolled.")
                    }
                    if Date().timeIntervalSince(started) > 120 || strips.count >= 100 {
                        warning = "The two-minute / 100-frame limit was reached. This image contains only the part captured so far."
                        break
                    }
                    status = "Capturing · \(totalHeight) pixels tall"
                    panel?.orderFrontRegardless()
                    try await pause(250)
                    panel?.orderOut(nil)
                    try await pause(150)
                    try requireTargetFocus()
                    if stopRequested { break }
                    let point = CGPoint(x: captureRect.midX, y: captureRect.midY)
                    CGWarpMouseCursorPosition(point)
                    guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                              wheel1: -Int32(captureRect.height * 0.45), wheel2: 0, wheel3: 0) else {
                        throw CaptureError("Could not generate a scroll event.")
                    }
                    wheel.location = point
                    wheel.post(tap: .cghidEventTap)
                    try await pause(150)
                    panel?.orderFrontRegardless()
                    try await pause(900) // allow browser layout, lazy images, and smooth scrolling to settle
                    panel?.orderOut(nil)
                    try await pause(150)
                    let next = try await screenshot(captureRect)
                    guard let nextPixels = ScrollCaptureStitcher.Pixels(next) else { throw CaptureError("Could not read the next capture.") }
                    panel?.orderFrontRegardless()
                    let previousPixels = pixels
                    let match = await Task.detached(priority: .userInitiated) {
                        ScrollCaptureStitcher.match(previous: previousPixels, next: nextPixels)
                    }.value
                    try Task.checkCancellation()
                    switch match {
                    case .unchanged:
                        unchanged += 1
                        if unchanged >= 3 { stopRequested = true }
                    case .moved(let delta):
                        unchanged = 0
                        guard (totalHeight + delta) * next.width <= 60_000_000,
                              totalHeight + delta <= 30_000 else {
                            warning = "The 30,000-pixel / 60-megapixel image limit was reached. This image contains only the part captured so far."
                            stopRequested = true
                            break
                        }
                        guard let strip = ScrollCaptureStitcher.bottomStrip(of: next, height: delta) else {
                            throw CaptureError("Could not combine the captured images.")
                        }
                        strips.append(strip)
                        totalHeight += delta
                        pixels = nextPixels
                    case .uncertain:
                        warning = "Could not reliably align the next viewport. This image contains only the part captured so far. Try a selection without fixed headers, animations, or repeating/blank content."
                        stopRequested = true
                    }
                }
                try Task.checkCancellation()
                panel?.orderOut(nil)
                let capturedStrips = strips
                guard let image = await Task.detached(priority: .userInitiated, operation: {
                    ScrollCaptureStitcher.compose(capturedStrips)
                }).value else { throw CaptureError("Could not allocate the combined image.") }
                try Task.checkCancellation()
                guard self.onSaved?(NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))) == true else {
                    throw CaptureError("Could not save the capture to history. Check your storage directory and available disk space.")
                }
                alert(warning == nil ? "Scrolling capture saved" : "Partial capture saved",
                      warning ?? "Saved a \(image.width) × \(image.height) image to history and the clipboard. Scrolling stopped changing the selected area.")
            } catch is CancellationError {
                // Cancellation deliberately leaves history and the clipboard untouched.
            } catch {
                panel?.orderOut(nil)
                alert("Scrolling capture failed", error.localizedDescription)
            }
        }
    }

    private func screenshot(_ rect: CGRect) async throws -> CGImage {
        try requireTargetFocus()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipmonster2-scroll-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exitStatus: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if process.isRunning { process.terminate() }
            }
        }
        try Task.checkCancellation()
        try requireTargetFocus()
        guard exitStatus == 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureError("Screen capture failed. Check Screen Recording permission and keep the selected screen connected.")
        }
        guard image.width * image.height <= 60_000_000 else { throw CaptureError("The selected area is too large.") }
        return image
    }

    private func requireTargetFocus() throws {
        guard let targetApp, !targetApp.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
            throw CaptureError("The browser lost focus. The capture was cancelled so another app would not be captured or scrolled.")
        }
    }

    private func pause(_ milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private func finish() {
        panel?.orderOut(nil)
        panel = nil
        for window in selectionWindows { window.orderOut(nil) }
        selectionWindows.removeAll()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
        escapeMonitor = nil
        localEscapeMonitor = nil
        if let originalPointer { CGWarpMouseCursorPosition(originalPointer) }
        originalPointer = nil
        onSaved = nil
        targetApp = nil
        task = nil
        isRunning = false
        status = ""
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private struct CaptureError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

private struct ScrollCaptureControls: View {
    @ObservedObject var capture: ScrollingCapture
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capture.status).font(.caption).lineLimit(1)
            HStack {
                Button("Stop & Save") { capture.stopAndSave() }
                Button("Cancel (Esc)") { capture.cancel() }
            }
        }.padding(12).frame(width: 286).background(Color(NSColor.windowBackgroundColor))
    }
}

private final class CaptureSelectionView: NSView {
    var selected: ((CGRect) -> Void)?
    private var anchor: CGPoint?
    private var selection = CGRect.zero

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                           width: abs(anchor.x - point.x), height: abs(anchor.y - point.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard selection.width >= 200, selection.height >= 150 else { return }
        selected?(selection)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSColor.white.withAlphaComponent(0.2).setFill()
            selection.fill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: selection)
            path.lineWidth = 3
            path.stroke()
        }
        let text = "Drag around the scrolling webpage content · Escape cancels"
        (text as NSString).draw(at: CGPoint(x: 24, y: bounds.height - 50), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.white
        ])
    }
}
