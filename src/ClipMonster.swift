import Cocoa
import SwiftUI

@main
struct ClipMonsterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var clipboardMonitor = ClipboardMonitor()
    var globalMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipMonster")
            button.action = #selector(togglePopover(_:))
        }
        
        let contentView = ContentView(monitor: clipboardMonitor)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        setupGlobalShortcut(shortcut: clipboardMonitor.globalShortcut)
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ShortcutChanged"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.setupGlobalShortcut(shortcut: self.clipboardMonitor.globalShortcut)
        }
    }
    
    func setupGlobalShortcut(shortcut: CustomShortcut) {
        if let currentMonitor = globalMonitor {
            NSEvent.removeMonitor(currentMonitor)
            globalMonitor = nil
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.rawValue == shortcut.modifiers && event.keyCode == shortcut.keyCode {
                DispatchQueue.main.async { self?.togglePopover(nil) }
            }
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
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
}

struct PersistedItem: Codable {
    let id: UUID
    let type: String
    let content: String
    let timestamp: Date
}

// MARK: - Clipboard Monitor
class ClipboardMonitor: ObservableObject {
    @Published var history: [ClipboardItem] = []
    @Published var selectedItems: Set<UUID> = []
    
    // Preferences
    @Published var historyLimit: Int = UserDefaults.standard.integer(forKey: "historyLimit") == 0 ? 50 : UserDefaults.standard.integer(forKey: "historyLimit") {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit") }
    }
    
    @Published var keepThroughReboot: Bool = UserDefaults.standard.bool(forKey: "keepThroughReboot") {
        didSet {
            UserDefaults.standard.set(keepThroughReboot, forKey: "keepThroughReboot")
            if keepThroughReboot { saveAllToDisk() } else { deleteDiskData() }
        }
    }
    
    @Published var storagePath: String = UserDefaults.standard.string(forKey: "storagePath") ?? "" {
        didSet { UserDefaults.standard.set(storagePath, forKey: "storagePath") }
    }
    
    @Published var globalShortcut: CustomShortcut {
        didSet {
            if let encoded = try? JSONEncoder().encode(globalShortcut) {
                UserDefaults.standard.set(encoded, forKey: "customGlobalShortcut")
            }
            NotificationCenter.default.post(name: NSNotification.Name("ShortcutChanged"), object: nil)
        }
    }
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "customGlobalShortcut"),
           let decoded = try? JSONDecoder().decode(CustomShortcut.self, from: data) {
            self.globalShortcut = decoded
        } else {
            // Default to Fn + V
            self.globalShortcut = CustomShortcut(keyCode: 9, modifiers: NSEvent.ModifierFlags.function.rawValue, keyString: "V")
        }
        
        lastChangeCount = pasteboard.changeCount
        if keepThroughReboot { loadFromDisk() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkForChanges() }
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
            newItem = ClipboardItem(id: newID, text: nil, image: firstImg, fileURL: nil, timestamp: Date())
        } else if let urlArray = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstURL = urlArray.first {
            newItem = ClipboardItem(id: newID, text: nil, image: nil, fileURL: firstURL, timestamp: Date())
        } else if let str = pasteboard.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { newItem = ClipboardItem(id: newID, text: trimmed, image: nil, fileURL: nil, timestamp: Date()) }
        }
        
        if let item = newItem {
            DispatchQueue.main.async {
                if let text = item.text { self.history.removeAll { $0.text == text } }
                else if let fileURL = item.fileURL { self.history.removeAll { $0.fileURL == fileURL } }
                
                self.history.insert(item, at: 0)
                while self.history.count > self.historyLimit {
                    let removed = self.history.removeLast()
                    self.deleteDiskItem(removed.id)
                }
                if self.keepThroughReboot {
                    self.saveItemToDisk(item)
                    self.saveIndex()
                }
            }
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
        pasteboard.clearContents()
        if let text = item.text { pasteboard.setString(text, forType: .string) }
        else if let image = item.image { pasteboard.writeObjects([image]) }
        else if let url = item.fileURL { pasteboard.writeObjects([url as NSURL]) }
        lastChangeCount = pasteboard.changeCount
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
            if let t = item.text { return PersistedItem(id: item.id, type: "text", content: t, timestamp: item.timestamp) }
            else if let u = item.fileURL { return PersistedItem(id: item.id, type: "url", content: u.absoluteString, timestamp: item.timestamp) }
            else { return PersistedItem(id: item.id, type: "image", content: "\(item.id.uuidString).png", timestamp: item.timestamp) }
        }
        if let data = try? JSONEncoder().encode(persisted) { try? data.write(to: indexURL) }
    }
    
    private func loadFromDisk() {
        guard isDriveAvailable() else { return }
        if let data = try? Data(contentsOf: indexURL), let persisted = try? JSONDecoder().decode([PersistedItem].self, from: data) {
            var loaded: [ClipboardItem] = []
            for p in persisted {
                if p.type == "text" { loaded.append(ClipboardItem(id: p.id, text: p.content, image: nil, fileURL: nil, timestamp: p.timestamp)) }
                else if p.type == "url", let url = URL(string: p.content) { loaded.append(ClipboardItem(id: p.id, text: nil, image: nil, fileURL: url, timestamp: p.timestamp)) }
                else if p.type == "image" {
                    if let img = NSImage(contentsOf: dataURL.appendingPathComponent(p.content)) {
                        loaded.append(ClipboardItem(id: p.id, text: nil, image: img, fileURL: nil, timestamp: p.timestamp))
                    }
                }
            }
            if loaded.count > historyLimit { loaded = Array(loaded.prefix(historyLimit)) }
            self.history = loaded
        }
    }
    
    private func deleteDiskItem(_ id: UUID) { try? FileManager.default.removeItem(at: dataURL.appendingPathComponent("\(id.uuidString).png")) }
    
    private func deleteDiskData() {
        if FileManager.default.fileExists(atPath: dataURL.path) {
            if storagePath.isEmpty { try? FileManager.default.removeItem(at: dataURL) }
            else {
                try? FileManager.default.removeItem(at: indexURL)
                let files = (try? FileManager.default.contentsOfDirectory(atPath: dataURL.path)) ?? []
                for file in files where file.hasSuffix(".png") { try? FileManager.default.removeItem(at: dataURL.appendingPathComponent(file)) }
            }
        }
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
            
            // Ignore if ONLY a modifier key is pressed (wait for the actual character key)
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
            return nil // Consume the event so it doesn't trigger anything else
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

struct ContentView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var showPreferences = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(showPreferences ? "Preferences" : "ClipMonster").font(.headline)
                Spacer()
                if !showPreferences {
                    Button(action: { monitor.purgeAll() }) { Image(systemName: "trash") }
                        .buttonStyle(.plain).help("Purge All")
                    Spacer().frame(width: 12)
                }
                Button(action: { showPreferences.toggle() }) {
                    Image(systemName: showPreferences ? "xmark.circle.fill" : "gearshape.fill")
                        .foregroundColor(showPreferences ? .secondary : .primary)
                }.buttonStyle(.plain)
            }.padding()
            Divider()
            
            if showPreferences { PreferencesView(monitor: monitor) }
            else {
                HistoryListView(monitor: monitor)
                
                if !monitor.selectedItems.isEmpty {
                    Divider()
                    Button(action: {
                        monitor.copySelected()
                    }) {
                        Text("Apply & Copy \(monitor.selectedItems.count) Items")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
            
            Divider()
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless).controlSize(.small)
            }.padding(8)
        }.frame(width: 340, height: 490)
    }
}

struct HistoryListView: View {
    @ObservedObject var monitor: ClipboardMonitor
    var body: some View {
        if monitor.history.isEmpty {
            VStack {
                Spacer()
                Image(systemName: "clipboard").font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 4)
                Text("No history yet.").foregroundColor(.secondary)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List { ForEach(monitor.history) { item in HistoryItemRow(item: item, monitor: monitor) } }
        }
    }
}

struct HistoryItemRow: View {
    let item: ClipboardItem
    @ObservedObject var monitor: ClipboardMonitor
    @State private var showCheckmark = false
    
    var body: some View {
        let isSelected = monitor.selectedItems.contains(item.id)
        
        HStack {
            Button(action: {
                if NSEvent.modifierFlags.contains(.shift) {
                    monitor.toggleSelection(for: item)
                } else {
                    monitor.copyToClipboard(item: item)
                    withAnimation { showCheckmark = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showCheckmark = false } }
                }
            }) {
                HStack {
                    if let img = item.image {
                        Image(nsImage: img).resizable().scaledToFill().frame(width: 40, height: 40).clipped().cornerRadius(4)
                        VStack(alignment: .leading) {
                            Text("Image").font(.subheadline)
                            Text("\(Int(img.size.width))x\(Int(img.size.height))").font(.caption).foregroundColor(.secondary)
                        }
                    } else if let url = item.fileURL {
                        Image(systemName: "doc").font(.title2).frame(width: 40)
                        Text(url.lastPathComponent).lineLimit(1)
                    } else if let txt = item.text {
                        Text(txt).lineLimit(2).font(.system(.body, design: .monospaced))
                    }
                    Spacer()
                    if showCheckmark { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).transition(.scale) }
                    else if isSelected { Image(systemName: "checkmark.square.fill").foregroundColor(.accentColor) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if !showCheckmark {
                Button(action: { monitor.deleteItem(item) }) { Image(systemName: "xmark").foregroundColor(.secondary).padding(4) }
                    .buttonStyle(.plain)
                    .onHover { hovering in if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
    }
}

struct PreferencesView: View {
    @ObservedObject var monitor: ClipboardMonitor
    var body: some View {
        Form {
            Section(header: Text("History Limits").font(.headline)) {
                Stepper(value: $monitor.historyLimit, in: 10...500, step: 10) { Text("Keep the last \(monitor.historyLimit) items") }
            }.padding(.top, 4)
            Divider().padding(.vertical, 4)
            
            Section(header: Text("Global Shortcut").font(.headline)) {
                HStack {
                    Text("Show Popover:")
                    Spacer()
                    ShortcutRecorder(shortcut: $monitor.globalShortcut)
                }
            }.padding(.top, 4)
            Divider().padding(.vertical, 4)
            
            Section(header: Text("Persistence").font(.headline)) {
                Toggle("Keep history across reboots", isOn: $monitor.keepThroughReboot)
                if monitor.keepThroughReboot {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage Location:").font(.caption).foregroundColor(.secondary)
                        HStack {
                            Text(monitor.storagePath.isEmpty ? "Default (App Support)" : monitor.storagePath).lineLimit(1).truncationMode(.middle).font(.caption)
                            Spacer()
                            Button("Change...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    monitor.storagePath = url.path
                                    monitor.keepThroughReboot = false; monitor.keepThroughReboot = true
                                }
                            }.controlSize(.mini)
                        }
                    }.padding(.leading, 16).padding(.top, 4)
                }
            }
            Divider().padding(.vertical, 4)
            
            Section(header: Text("Permissions").font(.headline)) {
                Text("For shortcuts to work, enable Accessibility for ClipMonster.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Divider().padding(.vertical, 4)
            
            Section(header: Text("Data Management").font(.headline)) {
                Button("Purge All Data") { monitor.purgeAll() }.foregroundColor(.red)
            }
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
