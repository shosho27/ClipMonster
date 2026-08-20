import Cocoa
import CryptoKit

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
        let fileName = "clipmonster2-\(stamp).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        // Avoid clobbering if two drags land in the same second
        let finalURL: URL
        if FileManager.default.fileExists(atPath: tempURL.path) {
            finalURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipmonster2-\(stamp)-\(UUID().uuidString.prefix(6)).png")
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

