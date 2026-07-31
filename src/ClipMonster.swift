import Cocoa
import SwiftUI
import ServiceManagement
import Vision
import CryptoKit
import Carbon

@main
struct ClipMonsterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

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
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipMonster")
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

// MARK: - Models
struct CustomShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var keyString: String
    
    var displayString: String {
        var str = ""
        let mods = NSEvent.ModifierFlags(rawValue: modifiers)
        if mods.contains(.control) { str += "⌃" }
        if mods.contains(.option) { str += "⌥" }
        if mods.contains(.shift) { str += "⇧" }
        if mods.contains(.command) { str += "⌘" }
        if mods.contains(.function) { str += "Fn " }
        str += keyString
        return str
    }
}

struct ClipboardItem: Identifiable {
    let id: UUID
    let text: String?
    let image: NSImage?
    let fileURL: URL?
    let timestamp: Date
    /// OCR text extracted from image (Vision).
    var ocrText: String?
    /// Stable content hash for image de-dupe.
    var imageHash: String?
    /// True while Vision OCR is running for this item.
    var isOCRing: Bool = false
    
    var searchableText: String {
        var parts: [String] = []
        if let text = text { parts.append(text) }
        if let ocrText = ocrText { parts.append(ocrText) }
        if let fileURL = fileURL {
            parts.append(fileURL.lastPathComponent)
            parts.append(fileURL.path)
        }
        if image != nil { parts.append("image") }
        return parts.joined(separator: " ")
    }
    
    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return searchableText.localizedCaseInsensitiveContains(q)
    }
    
    /// Build an `NSItemProvider` suitable for dragging into Finder, design apps, Terminal, etc.
    func makeDragItemProvider() -> NSItemProvider {
        if let image = image {
            return Self.imageItemProvider(image)
        }
        if let fileURL = fileURL {
            return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
        }
        if let text = text {
            return NSItemProvider(object: text as NSString)
        }
        return NSItemProvider()
    }
    
    private static let dragDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()
    
    private static func imageItemProvider(_ image: NSImage) -> NSItemProvider {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return NSItemProvider(object: image)
        }
        
        // Human-readable temp name for Terminal path drops
        let stamp = dragDateFormatter.string(from: Date())
        let fileName = "clipboard-\(stamp).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        // Avoid clobbering if two drags land in the same second
        let finalURL: URL
        if FileManager.default.fileExists(atPath: tempURL.path) {
            finalURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipboard-\(stamp)-\(UUID().uuidString.prefix(6)).png")
        } else {
            finalURL = tempURL
        }
        
        do {
            try pngData.write(to: finalURL)
        } catch {
            return NSItemProvider(object: image)
        }
        
        let provider = NSItemProvider(contentsOf: finalURL) ?? NSItemProvider()
        provider.suggestedName = fileName
        
        provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
            completion(pngData, nil)
            return nil
        }
        provider.registerObject(image, visibility: .all)
        provider.registerObject(finalURL as NSURL, visibility: .all)
        
        return provider
    }
    
    static func hashImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let digest = SHA256.hash(data: png)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - OCR (Apple Vision)
enum ImageOCR {
    static func recognizeText(in image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImageForOCR else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(joined.isEmpty ? nil : joined)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}

extension NSImage {
    var cgImageForOCR: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        if let cg = cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }
}

// MARK: - Drag session & temp cleanup
enum DragSession {
    static let began = Notification.Name("ClipMonsterDragBegan")
    static let ended = Notification.Name("ClipMonsterDragEnded")
    
    private static var active = false
    
    static func begin() {
        guard !active else { return }
        active = true
        NotificationCenter.default.post(name: began, object: nil)
        
        var globalMonitor: Any?
        var localMonitor: Any?
        
        let end: () -> Void = {
            guard active else { return }
            active = false
            if let g = globalMonitor {
                NSEvent.removeMonitor(g)
                globalMonitor = nil
            }
            if let l = localMonitor {
                NSEvent.removeMonitor(l)
                localMonitor = nil
            }
            NotificationCenter.default.post(name: ended, object: nil)
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            DispatchQueue.main.async { end() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            DispatchQueue.main.async { end() }
            return event
        }
    }
}

enum DragTempCleanup {
    /// Remove old ClipMonster / clipboard drag PNGs from the temp directory.
    static func run() {
        let tmp = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for name in names {
            let isOurs = name.hasPrefix("ClipMonster-") || name.hasPrefix("clipboard-")
            guard isOurs, name.hasSuffix(".png") else { continue }
            let url = tmp.appendingPathComponent(name)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modified = attrs[.modificationDate] as? Date,
               modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

struct PersistedItem: Codable {
    let id: UUID
    let type: String
    let content: String
    let timestamp: Date
    var ocrText: String?
    var imageHash: String?
}

// MARK: - Launch at Login
enum LaunchAtLogin {
    static let label = "com.sashornock.ClipMonster"
    
    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    
    static var isEnabled: Bool {
        if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
            return true
        }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }
    
    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            do {
                try setLoginItem(enabled)
                removeLaunchAgent()
                return
            } catch {
                if !enabled {
                    removeLaunchAgent()
                    if !isEnabled { return }
                }
            }
        }
        try setLaunchAgent(enabled)
    }
    
    @available(macOS 13.0, *)
    private static func setLoginItem(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
    
    private static func setLaunchAgent(_ enabled: Bool) throws {
        if enabled {
            let appPath = Bundle.main.bundlePath
            guard appPath.hasSuffix(".app") else {
                throw NSError(
                    domain: "ClipMonster",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Run the ClipMonster.app bundle so login launch can be configured."]
                )
            }
            
            let agentsDir = launchAgentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
            
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", appPath],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
        } else {
            removeLaunchAgent()
        }
    }
    
    private static func removeLaunchAgent() {
        try? FileManager.default.removeItem(at: launchAgentURL)
    }
}

// MARK: - Clipboard Monitor
class ClipboardMonitor: ObservableObject {
    @Published var history: [ClipboardItem] = []
    @Published var selectedItems: Set<UUID> = []
    
    @Published var historyLimit: Int = UserDefaults.standard.integer(forKey: "historyLimit") == 0 ? 50 : UserDefaults.standard.integer(forKey: "historyLimit") {
        didSet {
            UserDefaults.standard.set(historyLimit, forKey: "historyLimit")
            trimHistoryIfNeeded()
        }
    }
    
    /// When enabled, history is limited only by available memory/disk space.
    @Published var unlimitedHistory: Bool = UserDefaults.standard.bool(forKey: "unlimitedHistory") {
        didSet {
            UserDefaults.standard.set(unlimitedHistory, forKey: "unlimitedHistory")
            trimHistoryIfNeeded()
        }
    }
    
    @Published var keepThroughReboot: Bool = UserDefaults.standard.bool(forKey: "keepThroughReboot") {
        didSet {
            UserDefaults.standard.set(keepThroughReboot, forKey: "keepThroughReboot")
            if keepThroughReboot { saveAllToDisk() } else { deleteDiskData() }
        }
    }
    
    @Published var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @Published var launchAtLoginError: String? = nil
    
    /// After choosing an item, paste into the previous app (requires Accessibility).
    @Published var autoPaste: Bool = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }
    
    /// Run Vision OCR automatically when a new image is captured.
    @Published var autoOCR: Bool = UserDefaults.standard.bool(forKey: "autoOCR") {
        didSet { UserDefaults.standard.set(autoOCR, forKey: "autoOCR") }
    }
    
    @Published var storagePath: String = UserDefaults.standard.string(forKey: "storagePath") ?? "" {
        didSet { UserDefaults.standard.set(storagePath, forKey: "storagePath") }
    }
    @Published var storageError: String? = nil
    
    @Published var globalShortcut: CustomShortcut {
        didSet {
            if let encoded = try? JSONEncoder().encode(globalShortcut) {
                UserDefaults.standard.set(encoded, forKey: "customGlobalShortcut")
            }
            NotificationCenter.default.post(name: NSNotification.Name("ShortcutChanged"), object: nil)
        }
    }

    /// Global shortcut for pasting the latest image path into Terminal/CLI apps.
    @Published var pathPasteShortcut: CustomShortcut {
        didSet {
            if let encoded = try? JSONEncoder().encode(pathPasteShortcut) {
                UserDefaults.standard.set(encoded, forKey: "pathPasteShortcut")
            }
            NotificationCenter.default.post(name: NSNotification.Name("ShortcutChanged"), object: nil)
        }
    }
    @Published var pathPasteShortcutError: String? = nil
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "customGlobalShortcut"),
           let decoded = try? JSONDecoder().decode(CustomShortcut.self, from: data) {
            self.globalShortcut = decoded
        } else {
            self.globalShortcut = CustomShortcut(keyCode: 9, modifiers: NSEvent.ModifierFlags.function.rawValue, keyString: "V")
        }
        if let data = UserDefaults.standard.data(forKey: "pathPasteShortcut"),
           let decoded = try? JSONDecoder().decode(CustomShortcut.self, from: data) {
            self.pathPasteShortcut = decoded
        } else {
            self.pathPasteShortcut = CustomShortcut(
                keyCode: 9,
                modifiers: (NSEvent.ModifierFlags.command.union(.shift)).rawValue,
                keyString: "V"
            )
        }
        
        lastChangeCount = pasteboard.changeCount
        if keepThroughReboot { loadFromDisk() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkForChanges() }
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }
    
    func filteredHistory(query: String) -> [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return history }
        return history.filter { $0.matches(query: q) }
    }
    
    func isSensitive(_ pasteboard: NSPasteboard) -> Bool {
        if let types = pasteboard.types, types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) { return true }
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 8 && trimmed.count <= 64 && !trimmed.contains(" ") && !trimmed.contains("\n") {
                let hasLetter = trimmed.rangeOfCharacter(from: .letters) != nil
                let hasNumber = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
                let hasSymbol = trimmed.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
                if hasLetter && hasNumber && hasSymbol { return true }
            }
        }
        return false
    }
    
    func checkForChanges() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if isSensitive(pasteboard) { return }
        
        var newItem: ClipboardItem? = nil
        let newID = UUID()
        
        if let imgArray = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let firstImg = imgArray.first {
            let hash = ClipboardItem.hashImage(firstImg)
            newItem = ClipboardItem(
                id: newID,
                text: nil,
                image: firstImg,
                fileURL: nil,
                timestamp: Date(),
                ocrText: nil,
                imageHash: hash
            )
        } else if let urlArray = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstURL = urlArray.first {
            newItem = ClipboardItem(id: newID, text: nil, image: nil, fileURL: firstURL, timestamp: Date())
        } else if let str = pasteboard.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                newItem = ClipboardItem(id: newID, text: trimmed, image: nil, fileURL: nil, timestamp: Date())
            }
        }
        
        if let item = newItem {
            DispatchQueue.main.async {
                self.insertItem(item)
            }
        }
    }
    
    private func insertItem(_ item: ClipboardItem) {
        // De-dupe: text, file URL, or image content hash
        if let text = item.text {
            history.removeAll { $0.text == text }
        } else if let fileURL = item.fileURL {
            history.removeAll { $0.fileURL == fileURL }
        } else if let hash = item.imageHash {
            let removed = history.filter { $0.imageHash == hash }
            for r in removed { deleteDiskItem(r.id) }
            history.removeAll { $0.imageHash == hash }
        }
        
        history.insert(item, at: 0)
        trimHistoryIfNeeded()
        if keepThroughReboot {
            saveItemToDisk(item)
            saveIndex()
        }
        
        if autoOCR, item.image != nil {
            runOCR(for: item.id)
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
        pasteboard.clearContents()
        if let text = item.text { pasteboard.setString(text, forType: .string) }
        else if let image = item.image { pasteboard.writeObjects([image]) }
        else if let url = item.fileURL { pasteboard.writeObjects([url as NSURL]) }
        lastChangeCount = pasteboard.changeCount
    }
    
    /// Copy OCR text (or plain text) for an item to the pasteboard.
    func copyOCRText(for item: ClipboardItem) {
        let value = item.ocrText ?? item.text
        guard let value = value, !value.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }
    
    /// Write image to a temp (or persisted) PNG and open it in Preview.app.
    @discardableResult
    func openInPreview(_ item: ClipboardItem) -> Bool {
        if let fileURL = item.fileURL, item.image == nil {
            return NSWorkspace.shared.open(fileURL)
        }
        guard let image = item.image else { return false }
        guard let url = fileURLForImagePreview(item: item, image: image) else { return false }
        
        if let previewApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: previewApp, configuration: config)
            return true
        }
        return NSWorkspace.shared.open(url)
    }
    
    /// Select the image (or captured file) in Finder. Images use their persisted
    /// PNG when available; otherwise a temporary PNG is created for Finder.
    @discardableResult
    func revealInFinder(_ item: ClipboardItem) -> Bool {
        let url: URL?
        if let fileURL = item.fileURL, item.image == nil {
            url = fileURL
        } else if let image = item.image {
            url = fileURLForImagePreview(item: item, image: image)
        } else {
            url = nil
        }
        guard let url = url else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    /// Put this image's filesystem path on the clipboard for Terminal and other
    /// text-only applications. A temporary PNG is used when persistence is off.
    @discardableResult
    func copyImagePath(_ item: ClipboardItem) -> Bool {
        guard let image = item.image,
              let url = fileURLForImagePreview(item: item, image: image) else { return false }
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
        lastChangeCount = pasteboard.changeCount
        return true
    }

    /// This reads a just-taken screenshot directly from the pasteboard as a
    /// fallback, so the shortcut does not need to wait for the 0.5-second poll.
    @discardableResult
    func copyLatestImagePathToClipboard() -> Bool {
        if pasteboard.changeCount != lastChangeCount,
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            let hash = ClipboardItem.hashImage(image)
            if let existing = history.first(where: { $0.imageHash == hash }) {
                lastChangeCount = pasteboard.changeCount
                return copyImagePath(existing)
            }
            let item = ClipboardItem(
                id: UUID(), text: nil, image: image, fileURL: nil,
                timestamp: Date(), ocrText: nil, imageHash: hash
            )
            insertItem(item)
            lastChangeCount = pasteboard.changeCount
            return copyImagePath(item)
        }
        guard let latestImage = history.first(where: { $0.image != nil }) else { return false }
        return copyImagePath(latestImage)
    }
    
    private func fileURLForImagePreview(item: ClipboardItem, image: NSImage) -> URL? {
        // Prefer persisted PNG when available
        let persisted = dataURL.appendingPathComponent("\(item.id.uuidString).png")
        if FileManager.default.fileExists(atPath: persisted.path) {
            return persisted
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-preview-\(stamp).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
    
    func toggleSelection(for item: ClipboardItem) {
        if selectedItems.contains(item.id) { selectedItems.remove(item.id) }
        else { selectedItems.insert(item.id) }
    }
    
    func copySelected() {
        let itemsToCopy = history.filter { selectedItems.contains($0.id) }.reversed()
        pasteboard.clearContents()
        
        var objectsToWrite: [NSPasteboardWriting] = []
        var textComponents: [String] = []
        
        for item in itemsToCopy {
            if let txt = item.text { textComponents.append(txt) }
            if let img = item.image { objectsToWrite.append(img) }
            if let url = item.fileURL { objectsToWrite.append(url as NSURL) }
        }
        if !textComponents.isEmpty { objectsToWrite.append(textComponents.joined(separator: "\n\n") as NSString) }
        if !objectsToWrite.isEmpty { pasteboard.writeObjects(objectsToWrite) }
        
        selectedItems.removeAll()
        lastChangeCount = pasteboard.changeCount
    }
    
    func deleteItem(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        selectedItems.remove(item.id)
        if keepThroughReboot {
            deleteDiskItem(item.id)
            saveIndex()
        }
    }
    
    func purgeAll() {
        history.removeAll()
        selectedItems.removeAll()
        deleteDiskData()
    }

    /// Move persisted clipboard data to a user-selected directory without
    /// deleting unrelated files in either directory.
    func changeStorageDirectory(to directory: URL) {
        let destination = directory.standardizedFileURL
        let source = dataURL.standardizedFileURL
        guard destination != source else { return }
        
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let probe = destination.appendingPathComponent(".clipmonster-write-test-\(UUID().uuidString)")
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
        } catch {
            storageError = "ClipMonster cannot write to \(destination.path)."
            return
        }
        
        let previousStoragePath = storagePath
        storagePath = destination.path
        if keepThroughReboot {
            saveAllToDisk()
            deleteDiskData(at: source, removeDirectory: previousStoragePath.isEmpty)
        }
        storageError = nil
    }
    
    // MARK: - OCR
    
    func runOCR(for id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }),
              let image = history[index].image else { return }
        if history[index].isOCRing { return }
        if history[index].ocrText != nil { return }
        
        history[index].isOCRing = true
        ImageOCR.recognizeText(in: image) { [weak self] text in
            guard let self = self,
                  let idx = self.history.firstIndex(where: { $0.id == id }) else { return }
            self.history[idx].isOCRing = false
            self.history[idx].ocrText = text
            if self.keepThroughReboot { self.saveIndex() }
        }
    }
    
    func forceRunOCR(for id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }),
              let image = history[index].image else { return }
        history[index].isOCRing = true
        history[index].ocrText = nil
        ImageOCR.recognizeText(in: image) { [weak self] text in
            guard let self = self,
                  let idx = self.history.firstIndex(where: { $0.id == id }) else { return }
            self.history[idx].isOCRing = false
            self.history[idx].ocrText = text
            if self.keepThroughReboot { self.saveIndex() }
        }
    }
    
    // MARK: - Disk Persistence
    private var dataURL: URL {
        if storagePath.isEmpty {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let path = appSupport.appendingPathComponent("ClipMonster")
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            return path
        } else { return URL(fileURLWithPath: storagePath) }
    }
    
    private var indexURL: URL { return dataURL.appendingPathComponent("index.json") }
    
    private func isDriveAvailable() -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dataURL.path, isDirectory: &isDir) { return isDir.boolValue }
        do {
            try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
            return true
        } catch { return false }
    }
    
    private func saveAllToDisk() {
        guard isDriveAvailable() else { return }
        for item in history { saveItemToDisk(item) }
        saveIndex()
    }

    private func trimHistoryIfNeeded() {
        guard !unlimitedHistory else { return }
        while history.count > historyLimit {
            let removed = history.removeLast()
            selectedItems.remove(removed.id)
            deleteDiskItem(removed.id)
        }
        if keepThroughReboot { saveIndex() }
    }
    
    private func saveItemToDisk(_ item: ClipboardItem) {
        guard isDriveAvailable() else { return }
        if let img = item.image, let tiff = img.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: dataURL.appendingPathComponent("\(item.id.uuidString).png"))
        }
    }
    
    private func saveIndex() {
        guard isDriveAvailable() else { return }
        let persisted = history.map { item -> PersistedItem in
            if let t = item.text {
                return PersistedItem(id: item.id, type: "text", content: t, timestamp: item.timestamp, ocrText: nil, imageHash: nil)
            } else if let u = item.fileURL {
                return PersistedItem(id: item.id, type: "url", content: u.absoluteString, timestamp: item.timestamp, ocrText: nil, imageHash: nil)
            } else {
                return PersistedItem(
                    id: item.id,
                    type: "image",
                    content: "\(item.id.uuidString).png",
                    timestamp: item.timestamp,
                    ocrText: item.ocrText,
                    imageHash: item.imageHash
                )
            }
        }
        if let data = try? JSONEncoder().encode(persisted) { try? data.write(to: indexURL) }
    }
    
    private func loadFromDisk() {
        guard isDriveAvailable() else { return }
        if let data = try? Data(contentsOf: indexURL), let persisted = try? JSONDecoder().decode([PersistedItem].self, from: data) {
            var loaded: [ClipboardItem] = []
            for p in persisted {
                if p.type == "text" {
                    loaded.append(ClipboardItem(id: p.id, text: p.content, image: nil, fileURL: nil, timestamp: p.timestamp))
                } else if p.type == "url", let url = URL(string: p.content) {
                    loaded.append(ClipboardItem(id: p.id, text: nil, image: nil, fileURL: url, timestamp: p.timestamp))
                } else if p.type == "image" {
                    if let img = NSImage(contentsOf: dataURL.appendingPathComponent(p.content)) {
                        let hash = p.imageHash ?? ClipboardItem.hashImage(img)
                        loaded.append(ClipboardItem(
                            id: p.id,
                            text: nil,
                            image: img,
                            fileURL: nil,
                            timestamp: p.timestamp,
                            ocrText: p.ocrText,
                            imageHash: hash
                        ))
                    }
                }
            }
            if !unlimitedHistory, loaded.count > historyLimit {
                loaded = Array(loaded.prefix(historyLimit))
            }
            self.history = loaded
        }
    }
    
    private func deleteDiskItem(_ id: UUID) {
        try? FileManager.default.removeItem(at: dataURL.appendingPathComponent("\(id.uuidString).png"))
    }
    
    private func deleteDiskData() {
        deleteDiskData(at: dataURL, removeDirectory: storagePath.isEmpty)
    }
    
    /// For a user-selected directory, remove only files listed in ClipMonster's
    /// own index. The directory itself and unrelated images remain untouched.
    private func deleteDiskData(at directory: URL, removeDirectory: Bool) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        if removeDirectory {
            try? FileManager.default.removeItem(at: directory)
            return
        }
        
        let oldIndexURL = directory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: oldIndexURL),
           let persisted = try? JSONDecoder().decode([PersistedItem].self, from: data) {
            for item in persisted where item.type == "image" {
                let imageURL = directory.appendingPathComponent(item.content)
                try? FileManager.default.removeItem(at: imageURL)
            }
        }
        try? FileManager.default.removeItem(at: oldIndexURL)
    }
}

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
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
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

struct ContentView: View {
    @ObservedObject var monitor: ClipboardMonitor
    var appDelegate: AppDelegate?
    @State private var showPreferences = false
    @State private var searchText = ""
    @State private var focusedIndex = 0
    /// In-popover large image preview (Space / eye button).
    @State private var largePreviewItem: ClipboardItem? = nil
    @StateObject private var keyHandler = HistoryKeyHandler()
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Fixed header — always visible
                HStack {
                    Text(showPreferences ? "Preferences" : "ClipMonster").font(.headline)
                    Spacer()
                    if !showPreferences {
                        Button(action: { monitor.purgeAll() }) { Image(systemName: "trash") }
                            .buttonStyle(.plain).help("Purge All")
                        Spacer().frame(width: 12)
                    }
                    if showPreferences {
                        Button("Done") { showPreferences = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Spacer().frame(width: 8)
                    }
                    Button(action: { showPreferences.toggle() }) {
                        Image(systemName: showPreferences ? "xmark.circle.fill" : "gearshape.fill")
                            .foregroundColor(showPreferences ? .secondary : .primary)
                    }.buttonStyle(.plain)
                    .help(showPreferences ? "Close preferences" : "Preferences")
                }.padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
                
                if !showPreferences {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search history…", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                Divider()
                
                // Flexible middle — scrolls when content is tall (esp. Preferences)
                Group {
                    if showPreferences {
                        PreferencesView(monitor: monitor)
                    } else {
                        VStack(spacing: 0) {
                            HistoryListView(
                                monitor: monitor,
                                filtered: monitor.filteredHistory(query: searchText),
                                focusedIndex: $focusedIndex,
                                onActivate: { item in activate(item) },
                                onShowLargePreview: { item in largePreviewItem = item },
                                onOpenInPreview: { item in _ = monitor.openInPreview(item) },
                                onRevealInFinder: { item in _ = monitor.revealInFinder(item) },
                                onCopyImagePath: { item in _ = monitor.copyImagePath(item) }
                            )
                            
                            if !monitor.selectedItems.isEmpty {
                                Divider()
                                Button(action: {
                                    monitor.copySelected()
                                    if monitor.autoPaste {
                                        appDelegate?.autoPasteIntoPreviousApp()
                                    }
                                }) {
                                    Text("Apply & Copy \(monitor.selectedItems.count) Items")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Fixed footer — Quit always reachable
                Divider()
                HStack {
                    if !showPreferences {
                        Text("↑↓ ⏎ · Space · 2× Preview · Esc · 1–9")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("Scroll for more settings")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Quit ClipMonster") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            }
            
            if let previewItem = largePreviewItem, let img = previewItem.image {
                LargeImagePreviewOverlay(
                    image: img,
                    ocrPreview: previewItem.ocrText,
                    onOpenInPreview: {
                        _ = monitor.openInPreview(previewItem)
                    },
                    onDismiss: { largePreviewItem = nil }
                )
            }
        }
        .frame(width: 360, height: 540)
        .onAppear { bindKeyHandler(); keyHandler.install() }
        .onDisappear { keyHandler.remove() }
        .onChange(of: searchText) {
            focusedIndex = 0
            bindKeyHandler()
        }
        .onChange(of: showPreferences) {
            bindKeyHandler()
            if showPreferences {
                largePreviewItem = nil
                keyHandler.remove()
            } else {
                keyHandler.install()
            }
        }
        .onChange(of: focusedIndex) { bindKeyHandler() }
        .onChange(of: monitor.history.count) { bindKeyHandler() }
    }
    
    private func bindKeyHandler() {
        keyHandler.showPreferences = { showPreferences }
        keyHandler.searchText = { searchText }
        keyHandler.setSearchText = { searchText = $0 }
        keyHandler.focusedIndex = { focusedIndex }
        keyHandler.setFocusedIndex = { focusedIndex = $0 }
        keyHandler.filtered = { monitor.filteredHistory(query: searchText) }
        keyHandler.activate = { activate($0) }
        keyHandler.previewFocused = { item in
            if largePreviewItem != nil {
                largePreviewItem = nil
                return
            }
            if item.image != nil {
                largePreviewItem = item
            } else if item.fileURL != nil {
                _ = monitor.openInPreview(item)
            }
        }
        keyHandler.isLargePreviewVisible = { largePreviewItem != nil }
        keyHandler.dismissLargePreview = { largePreviewItem = nil }
    }
    
    private func activate(_ item: ClipboardItem) {
        if NSEvent.modifierFlags.contains(.shift) {
            monitor.toggleSelection(for: item)
            return
        }
        monitor.copyToClipboard(item: item)
        if monitor.autoPaste {
            appDelegate?.autoPasteIntoPreviousApp()
        }
    }
}

/// Full-size image preview overlaid on the popover.
struct LargeImagePreviewOverlay: View {
    let image: NSImage
    let ocrPreview: String?
    var onOpenInPreview: () -> Void
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            VStack(spacing: 12) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 380)
                    .cornerRadius(8)
                    .shadow(radius: 12)
                
                if let ocr = ocrPreview, !ocr.isEmpty {
                    Text(ocr)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                
                HStack(spacing: 12) {
                    Button("Open in Preview") {
                        onOpenInPreview()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("Close") { onDismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(16)
        }
        .transition(.opacity)
    }
}

struct HistoryListView: View {
    @ObservedObject var monitor: ClipboardMonitor
    let filtered: [ClipboardItem]
    @Binding var focusedIndex: Int
    var onActivate: (ClipboardItem) -> Void
    var onShowLargePreview: (ClipboardItem) -> Void
    var onOpenInPreview: (ClipboardItem) -> Void
    var onRevealInFinder: (ClipboardItem) -> Void
    var onCopyImagePath: (ClipboardItem) -> Void
    
    var body: some View {
        if monitor.history.isEmpty {
            VStack {
                Spacer()
                Image(systemName: "clipboard").font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 4)
                Text("No history yet.").foregroundColor(.secondary)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            VStack {
                Spacer()
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 4)
                Text("No matches.").foregroundColor(.secondary)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                    HistoryItemRow(
                        item: item,
                        monitor: monitor,
                        isFocused: index == focusedIndex,
                        onActivate: { onActivate(item) },
                        onShowLargePreview: { onShowLargePreview(item) },
                        onOpenInPreview: { onOpenInPreview(item) },
                        onRevealInFinder: { onRevealInFinder(item) },
                        onCopyImagePath: { onCopyImagePath(item) }
                    )
                    .listRowBackground(
                        index == focusedIndex
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
            }
        }
    }
}

struct HistoryItemRow: View {
    let item: ClipboardItem
    @ObservedObject var monitor: ClipboardMonitor
    var isFocused: Bool = false
    var onActivate: () -> Void
    var onShowLargePreview: () -> Void
    var onOpenInPreview: () -> Void
    var onRevealInFinder: () -> Void
    var onCopyImagePath: () -> Void
    
    @State private var showCheckmark = false
    
    private var canDrag: Bool {
        item.image != nil || item.fileURL != nil || item.text != nil
    }
    
    private var dragHelp: String {
        if item.image != nil {
            return "Click to copy · Double-click opens Preview · Space / eye for large preview"
        }
        if item.fileURL != nil {
            return "Click to copy · Double-click to open file · Drag to place"
        }
        return "Click to copy · Drag to place text"
    }
    
    var body: some View {
        let isSelected = monitor.selectedItems.contains(item.id)
        
        HStack(spacing: 4) {
            // Thumbnail (images only): click = large preview, double-click = Preview.app
            if let img = item.image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipped()
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .help("Click: large preview · Double-click: open in Preview")
                    .onTapGesture(count: 2) { onOpenInPreview() }
                    .onTapGesture(count: 1) { onShowLargePreview() }
                    .onDrag {
                        DragSession.begin()
                        return item.makeDragItemProvider()
                    } preview: {
                        dragPreview
                    }
            }
            
            // Main row area: click = copy/paste, double-click = Preview for images/files
            HStack(spacing: 8) {
                if let img = item.image {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Image").font(.subheadline)
                        if item.isOCRing {
                            Text("OCR…").font(.caption).foregroundColor(.secondary)
                        } else if let ocr = item.ocrText, !ocr.isEmpty {
                            Text(ocr).lineLimit(2).font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("\(Int(img.size.width))×\(Int(img.size.height))").font(.caption).foregroundColor(.secondary)
                        }
                    }
                } else if let url = item.fileURL {
                    Image(systemName: "doc").font(.title2).frame(width: 40)
                    Text(url.lastPathComponent).lineLimit(1)
                } else if let txt = item.text {
                    Text(txt).lineLimit(2).font(.system(.body, design: .monospaced))
                }
                Spacer()
                if showCheckmark {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).transition(.scale)
                } else if isSelected {
                    Image(systemName: "checkmark.square.fill").foregroundColor(.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help(dragHelp)
            .onTapGesture(count: 2) {
                if item.image != nil || item.fileURL != nil {
                    onOpenInPreview()
                }
            }
            .onTapGesture(count: 1) {
                if NSEvent.modifierFlags.contains(.shift) {
                    monitor.toggleSelection(for: item)
                } else {
                    onActivate()
                    withAnimation { showCheckmark = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation { showCheckmark = false }
                    }
                }
            }
            .onDrag {
                guard canDrag else { return NSItemProvider() }
                DragSession.begin()
                return item.makeDragItemProvider()
            } preview: {
                dragPreview
            }
            
            // Image actions: large preview, Preview.app, Finder, OCR, delete
            if item.image != nil {
                Button(action: { onShowLargePreview() }) {
                    Image(systemName: "eye")
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Large preview (Space)")
                
                Button(action: { onOpenInPreview() }) {
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Open in Preview")

                Button(action: { onRevealInFinder() }) {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Reveal image in Finder")

                Button(action: { onCopyImagePath() }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Copy image path")
                
                if item.isOCRing {
                    ProgressView().controlSize(.small).frame(width: 20)
                } else if let ocr = item.ocrText, !ocr.isEmpty {
                    Button(action: {
                        monitor.copyOCRText(for: item)
                        withAnimation { showCheckmark = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation { showCheckmark = false }
                        }
                    }) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.accentColor)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Copy OCR text")
                } else {
                    Button(action: { monitor.forceRunOCR(for: item.id) }) {
                        Image(systemName: "text.viewfinder")
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Extract text (OCR)")
                }
            }
            
            if !showCheckmark {
                Button(action: { monitor.deleteItem(item) }) {
                    Image(systemName: "xmark").foregroundColor(.secondary).padding(4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .padding(6)
        .background(
            isSelected ? Color.accentColor.opacity(0.15)
                : (isFocused ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .cornerRadius(6)
    }
    
    @ViewBuilder
    private var dragPreview: some View {
        if let img = item.image {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 160, maxHeight: 160)
                .cornerRadius(6)
                .shadow(radius: 4)
        } else if let url = item.fileURL {
            Label(url.lastPathComponent, systemImage: "doc")
                .padding(8)
                .background(.regularMaterial)
                .cornerRadius(6)
        } else if let txt = item.text {
            Text(txt)
                .lineLimit(3)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: 180, alignment: .leading)
                .background(.regularMaterial)
                .cornerRadius(6)
        } else {
            EmptyView()
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var monitor: ClipboardMonitor
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                prefSection("History Limits") {
                    Toggle("Keep unlimited history", isOn: $monitor.unlimitedHistory)
                    Text("Stores every captured item until you delete or purge it. Disk space and memory are the only limits.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !monitor.unlimitedHistory {
                        Stepper(value: $monitor.historyLimit, in: 10...500, step: 10) {
                            Text("Keep the last \(monitor.historyLimit) items")
                        }
                    }
                }
                
                prefSection("Paste") {
                    Toggle("Auto-paste into previous app", isOn: $monitor.autoPaste)
                    Text("After you pick an item, simulates ⌘V. Needs Accessibility.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                prefSection("OCR") {
                    Toggle("Auto-OCR new images", isOn: $monitor.autoOCR)
                    Text("Uses on-device Apple Vision. You can also OCR a single image from its row.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                prefSection("Global Shortcut") {
                    HStack {
                        Text("Show Popover:")
                        Spacer()
                        ShortcutRecorder(shortcut: $monitor.globalShortcut)
                    }
                    HStack {
                        Text("Paste latest image path:")
                        Spacer()
                        ShortcutRecorder(shortcut: $monitor.pathPasteShortcut)
                    }
                    Text("Copies the newest screenshot's PNG path and pastes it into the focused app. Requires Accessibility; default: ⌘⇧V.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = monitor.pathPasteShortcutError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                prefSection("Startup") {
                    Toggle("Start ClipMonster at login", isOn: Binding(
                        get: { monitor.launchAtLogin },
                        set: { monitor.setLaunchAtLogin($0) }
                    ))
                    Text("Launches in the menu bar after you log in or reboot.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let err = monitor.launchAtLoginError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                prefSection("Persistence") {
                    Toggle("Keep history across reboots", isOn: $monitor.keepThroughReboot)
                    if monitor.keepThroughReboot {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Storage Location:").font(.caption).foregroundColor(.secondary)
                            HStack {
                                Text(monitor.storagePath.isEmpty ? "Default (App Support)" : monitor.storagePath)
                                    .lineLimit(1).truncationMode(.middle).font(.caption)
                                Spacer()
                                Button("Change...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.canCreateDirectories = true
                                    if panel.runModal() == .OK, let url = panel.url {
                                        monitor.changeStorageDirectory(to: url)
                                    }
                                }.controlSize(.mini)
                            }
                            if let error = monitor.storageError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                
                prefSection("Permissions") {
                    Text("Accessibility is required for the global shortcut and auto-paste.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                
                prefSection("Data Management") {
                    Button("Purge All Data") { monitor.purgeAll() }
                        .foregroundColor(.red)
                }
                
                // Extra space so last controls aren't tight against the footer
                Color.clear.frame(height: 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private func prefSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Divider()
    }
}
