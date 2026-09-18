import Cocoa

struct ClipboardItem: Identifiable {
    let id: UUID
    let text: String?
    /// Small ImageIO downsample for the history list. Never the full screenshot.
    let thumbnail: NSImage?
    /// PNG on disk. Full pixels are loaded only for markup, copy, or Preview.
    var imageFileURL: URL?
    let fileURL: URL?
    let timestamp: Date
    /// OCR text extracted from image (Vision).
    var ocrText: String? = nil
    /// SHA-256 of the PNG file bytes, for de-dupe.
    var imageHash: String? = nil
    /// True while Vision OCR is running for this item.
    var isOCRing: Bool = false
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    
    var hasImage: Bool { imageFileURL != nil }
    
    var searchableText: String {
        var parts: [String] = []
        if let text = text { parts.append(text) }
        if let ocrText = ocrText { parts.append(ocrText) }
        if let fileURL = fileURL {
            parts.append(fileURL.lastPathComponent)
            parts.append(fileURL.path)
        }
        if hasImage { parts.append("image") }
        return parts.joined(separator: " ")
    }
    
    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return searchableText.localizedCaseInsensitiveContains(q)
    }
    
    func loadFullImage() -> NSImage? {
        guard let url = imageFileURL else { return nil }
        return NSImage(contentsOf: url)
    }
    
    func previewImage() -> NSImage? {
        guard let url = imageFileURL else { return nil }
        return ImageStore.downsampledImage(at: url, maxPixel: ImageStore.previewMaxPixel) ?? thumbnail
    }
    
    func ocrImage() -> NSImage? {
        guard let url = imageFileURL else { return nil }
        return ImageStore.downsampledImage(at: url, maxPixel: ImageStore.ocrMaxPixel)
    }
    
    /// Build an `NSItemProvider` suitable for dragging into Finder, design apps, Terminal, etc.
    func makeDragItemProvider() -> NSItemProvider {
        if let imageURL = imageFileURL {
            return Self.imageFileProvider(imageURL)
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
    
    private static func imageFileProvider(_ imageURL: URL) -> NSItemProvider {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            return NSItemProvider()
        }
        
        let stamp = dragDateFormatter.string(from: Date())
        let fileName = "clipmonster2-\(stamp).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let finalURL: URL
        if FileManager.default.fileExists(atPath: tempURL.path) {
            finalURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipmonster2-\(stamp)-\(UUID().uuidString.prefix(6)).png")
        } else {
            finalURL = tempURL
        }
        
        do {
            try FileManager.default.copyItem(at: imageURL, to: finalURL)
        } catch {
            return NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
        }
        
        let provider = NSItemProvider(contentsOf: finalURL) ?? NSItemProvider()
        provider.suggestedName = fileName
        
        provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
            completion(try? Data(contentsOf: imageURL, options: [.mappedIfSafe]), nil)
            return nil
        }
        provider.registerObject(finalURL as NSURL, visibility: .all)
        
        return provider
    }
}
