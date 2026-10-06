import Cocoa
import SwiftUI

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
    
    /// When enabled, history is limited only by available disk space.
    @Published var unlimitedHistory: Bool = UserDefaults.standard.bool(forKey: "unlimitedHistory") {
        didSet {
            UserDefaults.standard.set(unlimitedHistory, forKey: "unlimitedHistory")
            trimHistoryIfNeeded()
        }
    }
    
    @Published var keepThroughReboot: Bool = UserDefaults.standard.bool(forKey: "keepThroughReboot") {
        didSet {
            UserDefaults.standard.set(keepThroughReboot, forKey: "keepThroughReboot")
            if keepThroughReboot { saveIndex() }
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
            self.globalShortcut = CustomShortcut(
                keyCode: 9,
                modifiers: (NSEvent.ModifierFlags.control.union(.option)).rawValue,
                keyString: "V"
            )
        }
        if let data = UserDefaults.standard.data(forKey: "pathPasteShortcut"),
           let decoded = try? JSONDecoder().decode(CustomShortcut.self, from: data) {
            self.pathPasteShortcut = decoded
        } else {
            self.pathPasteShortcut = CustomShortcut(
                keyCode: 9,
                modifiers: (NSEvent.ModifierFlags.command.union(.shift).union(.option)).rawValue,
                keyString: "V"
            )
        }
        
        lastChangeCount = pasteboard.changeCount
        if keepThroughReboot {
            loadFromDisk()
        } else {
            deleteDiskData()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkForChanges() }
    }
    
    func prepareForTermination() {
        if keepThroughReboot {
            saveIndex()
        } else {
            deleteDiskData()
        }
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
        
        if let captured = ImageStore.pngFromPasteboard(pasteboard) {
            newItem = makeImageItem(id: newID, png: captured.data, pixelWidth: captured.pixelWidth, pixelHeight: captured.pixelHeight)
        } else if let urlArray = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstURL = urlArray.first {
            newItem = ClipboardItem(id: newID, text: nil, thumbnail: nil, imageFileURL: nil, fileURL: firstURL, timestamp: Date())
        } else if let str = pasteboard.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                newItem = ClipboardItem(id: newID, text: trimmed, thumbnail: nil, imageFileURL: nil, fileURL: nil, timestamp: Date())
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
        saveIndex()
        
        if autoOCR, item.hasImage {
            runOCR(for: item.id)
        }
    }

    /// Adds a flattened annotated copy without modifying the original capture,
    /// and makes that image the current system clipboard value.
    @discardableResult
    func addAnnotatedImage(_ image: NSImage) -> ClipboardItem {
        let id = UUID()
        let item: ClipboardItem
        if let png = ImageStore.pngData(from: image),
           let created = makeImageItem(id: id, png: png) {
            item = created
        } else {
            item = ClipboardItem(id: id, text: nil, thumbnail: nil, imageFileURL: nil, fileURL: nil, timestamp: Date())
        }
        insertItem(item)
        copyToClipboard(item: item)
        return item
    }

    /// Capture fails atomically: never add an empty row or clear the clipboard
    /// when PNG encoding or storage fails.
    @discardableResult
    func addCapturedImage(_ image: NSImage) -> ClipboardItem? {
        guard let png = ImageStore.pngData(from: image),
              let item = makeImageItem(id: UUID(), png: png) else { return nil }
        insertItem(item)
        copyToClipboard(item: item)
        return item
    }
    
    func copyToClipboard(item: ClipboardItem) {
        pasteboard.clearContents()
        if let text = item.text {
            pasteboard.setString(text, forType: .string)
        } else if let url = item.imageFileURL, let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            pasteboard.setData(data, forType: .png)
        } else if let url = item.fileURL {
            pasteboard.writeObjects([url as NSURL])
        }
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
        if let fileURL = item.fileURL, !item.hasImage {
            return NSWorkspace.shared.open(fileURL)
        }
        guard let url = fileURLForImagePreview(item: item) else { return false }
        
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
        if let fileURL = item.fileURL, !item.hasImage {
            url = fileURL
        } else {
            url = fileURLForImagePreview(item: item)
        }
        guard let url = url else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    /// Put this image's filesystem path on the clipboard for Terminal and other
    /// text-only applications. A temporary PNG is used when persistence is off.
    @discardableResult
    func copyImagePath(_ item: ClipboardItem) -> Bool {
        guard let url = fileURLForImagePreview(item: item) else { return false }
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
           let captured = ImageStore.pngFromPasteboard(pasteboard) {
            let hash = ImageStore.hashPNG(captured.data)
            if let existing = history.first(where: { $0.imageHash == hash }) {
                lastChangeCount = pasteboard.changeCount
                return copyImagePath(existing)
            }
            if let item = makeImageItem(id: UUID(), png: captured.data, pixelWidth: captured.pixelWidth, pixelHeight: captured.pixelHeight) {
                insertItem(item)
                lastChangeCount = pasteboard.changeCount
                return copyImagePath(item)
            }
        }
        guard let latestImage = history.first(where: { $0.hasImage }) else { return false }
        return copyImagePath(latestImage)
    }
    
    private func fileURLForImagePreview(item: ClipboardItem) -> URL? {
        if let url = item.imageFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
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
            if let url = item.imageFileURL, let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                pasteboard.setData(data, forType: .png)
            }
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
        deleteDiskItem(item.id)
        saveIndex()
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
            storageError = "ClipMonster 2.0 cannot write to \(destination.path)."
            return
        }
        
        let previousStoragePath = storagePath
        for item in history {
            guard let src = item.imageFileURL else { continue }
            let destFile = destination.appendingPathComponent("\(item.id.uuidString).png")
            if src.standardizedFileURL != destFile {
                try? FileManager.default.copyItem(at: src, to: destFile)
            }
        }
        
        storagePath = destination.path
        history = history.map { item in
            guard item.hasImage else { return item }
            var copy = item
            copy.imageFileURL = destination.appendingPathComponent("\(item.id.uuidString).png")
            return copy
        }
        saveIndex()
        deleteDiskData(at: source, removeDirectory: previousStoragePath.isEmpty)
        storageError = nil
    }
    
    // MARK: - OCR
    
    func runOCR(for id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        guard history[index].hasImage else { return }
        if history[index].isOCRing { return }
        if history[index].ocrText != nil { return }
        guard let image = history[index].ocrImage() else { return }
        
        history[index].isOCRing = true
        ImageOCR.recognizeText(in: image) { [weak self] text in
            guard let self = self,
                  let idx = self.history.firstIndex(where: { $0.id == id }) else { return }
            self.history[idx].isOCRing = false
            self.history[idx].ocrText = text
            self.saveIndex()
        }
    }
    
    func forceRunOCR(for id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        guard history[index].hasImage else { return }
        guard let image = history[index].ocrImage() else { return }
        history[index].isOCRing = true
        history[index].ocrText = nil
        ImageOCR.recognizeText(in: image) { [weak self] text in
            guard let self = self,
                  let idx = self.history.firstIndex(where: { $0.id == id }) else { return }
            self.history[idx].isOCRing = false
            self.history[idx].ocrText = text
            self.saveIndex()
        }
    }
    
    // MARK: - Disk Persistence
    private var dataURL: URL {
        if storagePath.isEmpty {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let path = appSupport.appendingPathComponent("ClipMonster 2.0")
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
    
    private func makeImageItem(id: UUID, png: Data, pixelWidth: Int? = nil, pixelHeight: Int? = nil, timestamp: Date = Date(), ocrText: String? = nil) -> ClipboardItem? {
        guard isDriveAvailable() else { return nil }
        let url = dataURL.appendingPathComponent("\(id.uuidString).png")
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        let size: (width: Int, height: Int)
        if let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 {
            size = (w, h)
        } else {
            size = ImageStore.pixelSize(of: png) ?? ImageStore.pixelSize(at: url) ?? (0, 0)
        }
        return ClipboardItem(
            id: id,
            text: nil,
            thumbnail: ImageStore.thumbnail(at: url),
            imageFileURL: url,
            fileURL: nil,
            timestamp: timestamp,
            ocrText: ocrText,
            imageHash: ImageStore.hashPNG(png),
            pixelWidth: size.width,
            pixelHeight: size.height
        )
    }

    private func trimHistoryIfNeeded() {
        guard !unlimitedHistory else { return }
        while history.count > historyLimit {
            let removed = history.removeLast()
            selectedItems.remove(removed.id)
            deleteDiskItem(removed.id)
        }
        saveIndex()
    }
    
    private func saveIndex() {
        guard isDriveAvailable() else { return }
        let persisted = history.map { item -> PersistedItem in
            if let t = item.text {
                return PersistedItem(id: item.id, type: "text", content: t, timestamp: item.timestamp, ocrText: nil, imageHash: nil, pixelWidth: nil, pixelHeight: nil)
            } else if let u = item.fileURL {
                return PersistedItem(id: item.id, type: "url", content: u.absoluteString, timestamp: item.timestamp, ocrText: nil, imageHash: nil, pixelWidth: nil, pixelHeight: nil)
            } else {
                return PersistedItem(
                    id: item.id,
                    type: "image",
                    content: "\(item.id.uuidString).png",
                    timestamp: item.timestamp,
                    ocrText: item.ocrText,
                    imageHash: item.imageHash,
                    pixelWidth: item.pixelWidth > 0 ? item.pixelWidth : nil,
                    pixelHeight: item.pixelHeight > 0 ? item.pixelHeight : nil
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
                    loaded.append(ClipboardItem(id: p.id, text: p.content, thumbnail: nil, imageFileURL: nil, fileURL: nil, timestamp: p.timestamp))
                } else if p.type == "url", let url = URL(string: p.content) {
                    loaded.append(ClipboardItem(id: p.id, text: nil, thumbnail: nil, imageFileURL: nil, fileURL: url, timestamp: p.timestamp))
                } else if p.type == "image" {
                    let url = dataURL.appendingPathComponent(p.content)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    let size: (Int, Int)
                    if let w = p.pixelWidth, let h = p.pixelHeight, w > 0, h > 0 {
                        size = (w, h)
                    } else {
                        size = ImageStore.pixelSize(at: url) ?? (0, 0)
                    }
                    loaded.append(ClipboardItem(
                        id: p.id,
                        text: nil,
                        thumbnail: ImageStore.thumbnail(at: url),
                        imageFileURL: url,
                        fileURL: nil,
                        timestamp: p.timestamp,
                        ocrText: p.ocrText,
                        imageHash: ImageStore.hashFile(at: url) ?? p.imageHash,
                        pixelWidth: size.0,
                        pixelHeight: size.1
                    ))
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
