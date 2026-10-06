import Cocoa
import SwiftUI
import ImageIO

@MainActor
final class ScrollingCapture: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    private var task: Task<Void, Never>?
    @Published private(set) var isChoosingPage = false
    private var clickMonitor: Any?
    private var selectionTask: Task<Void, Never>?
    private var armingTimeout: Task<Void, Never>?
    private var cancelHotKey: CaptureEscapeHotKey?
    private var screenshotProcess: Process?
    private var scrollPoint: CGPoint?
    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private var targetApp: NSRunningApplication?
    private var originalPointer: CGPoint?
    private var stopRequested = false
    private var onSaved: ((NSImage) -> Bool)?

    func start(target: NSRunningApplication?, onSaved: @escaping (NSImage) -> Bool) {
        guard !isRunning else { return }
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
        self.onSaved = onSaved
        originalPointer = CGEvent(source: nil)?.location
        stopRequested = false
        isRunning = true
        isChoosingPage = true
        status = "Click inside the webpage to capture · Esc cancels"
        cancelHotKey = CaptureEscapeHotKey { [weak self] in
            Task { @MainActor in self?.cancel() }
        }
        cancelHotKey?.register()
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
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let screen {
            showControls(at: CGRect(x: screen.visibleFrame.maxX - 350, y: screen.visibleFrame.maxY - 130, width: 340, height: 110))
        }
        // Observe the ordinary click; no screen-covering window intercepts it.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            let point = event.cgEvent?.location ?? CGEvent(source: nil)?.location ?? .zero
            Task { @MainActor in self?.choosePage(at: point) }
        }
        target?.activate(options: [])
        armingTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled, let self, isChoosingPage else { return }
            cancel()
        }
    }

    private func showControls(at rect: CGRect) {
        let control = NSPanel(contentRect: rect,
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        control.level = .floating
        control.isFloatingPanel = true
        control.hidesOnDeactivate = false
        control.isMovableByWindowBackground = true
        control.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        control.contentView = NSHostingView(rootView: ScrollCaptureControls(capture: self))
        panel = control
        control.orderFrontRegardless()
    }

    private func choosePage(at point: CGPoint) {
        guard isChoosingPage, selectionTask == nil,
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        let pid = app.processIdentifier
        status = "Finding webpage content… · Esc cancels"
        selectionTask = Task { [weak self] in
            var frame = await Task.detached(priority: .userInitiated) {
                CapturePageTarget.resolve(point: point, pid: pid, screens: screens)
            }.value
            // Chromium may populate its accessibility tree asynchronously on
            // the first lookup. Retry the same click once, without blocking UI.
            if frame == nil, !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
                frame = await Task.detached(priority: .userInitiated) {
                    CapturePageTarget.resolve(point: point, pid: pid, screens: screens)
                }.value
            }
            guard let self, !Task.isCancelled, isChoosingPage else { return }
            selectionTask = nil
            guard let frame else {
                status = "Click inside page content, away from the toolbar"
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                status = "Click the webpage again to choose it"
                return
            }
            targetApp = app
            scrollPoint = point
            isChoosingPage = false
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            armingTimeout?.cancel()
            armingTimeout = nil
            beginCapture(rect: frame)
        }
    }

    func stopAndSave() { stopRequested = true; status = "Saving capture…" }

    func cancel() {
        // Release all UI and event hooks immediately, even if a screenshot or
        // background alignment is still finishing.
        task?.cancel()
        selectionTask?.cancel()
        selectionTask = nil
        if let screenshotProcess, screenshotProcess.isRunning { screenshotProcess.terminate() }
        releaseControls()
        if task == nil { finish() }
    }

    private func beginCapture(rect: CGRect) {
        guard isRunning, task == nil else { return }
        let captureRect = rect.integral
        panel?.orderOut(nil)
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
                    let point = scrollPoint ?? CGPoint(x: captureRect.midX, y: captureRect.midY)
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
                        warning = "Could not reliably align the next viewport. This image contains only the part captured so far. Fixed headers, animations, or repeating/blank content may prevent reliable stitching."
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
                releaseControls()
                alert(warning == nil ? "Scrolling capture saved" : "Partial capture saved",
                      warning ?? "Saved a \(image.width) × \(image.height) image to history and the clipboard. Scrolling stopped changing the selected area.")
            } catch is CancellationError {
                // Cancellation deliberately leaves history and the clipboard untouched.
            } catch {
                releaseControls()
                alert("Scrolling capture failed", error.localizedDescription)
            }
        }
    }

    private func screenshot(_ rect: CGRect) async throws -> CGImage {
        try requireTargetFocus()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipmonster2-scroll-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        screenshotProcess = process
        defer { screenshotProcess = nil }
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
              let image = ScrollCaptureImageDecoder.load(url) else {
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
        releaseControls()
        if let originalPointer { CGWarpMouseCursorPosition(originalPointer) }
        originalPointer = nil
        onSaved = nil
        targetApp = nil
        scrollPoint = nil
        task = nil
        isRunning = false
        status = ""
    }

    private func releaseControls() {
        panel?.orderOut(nil)
        panel = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
        escapeMonitor = nil
        localEscapeMonitor = nil
        cancelHotKey?.unregister()
        cancelHotKey = nil
        armingTimeout?.cancel()
        armingTimeout = nil
        isChoosingPage = false
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
                if !capture.isChoosingPage { Button("Stop & Save") { capture.stopAndSave() } }
                Button("Cancel (Esc)") { capture.cancel() }
            }
        }.padding(12).frame(width: 286).background(Color(NSColor.windowBackgroundColor))
    }
}
