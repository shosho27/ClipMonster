import Cocoa
import ImageIO
import CryptoKit

/// Disk-backed PNG helpers. Full screenshots stay on disk; RAM only gets
/// ImageIO downsamples (thumbnails / previews / OCR).
enum ImageStore {
    static let thumbnailMaxPixel: CGFloat = 128
    static let previewMaxPixel: CGFloat = 720
    static let ocrMaxPixel: CGFloat = 2048
    
    private static let noCache: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
    
    struct PNGCapture {
        let data: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }
    
    static func pngFromPasteboard(_ pasteboard: NSPasteboard) -> PNGCapture? {
        if let png = pasteboard.data(forType: .png), let size = pixelSize(of: png) {
            return PNGCapture(data: png, pixelWidth: size.width, pixelHeight: size.height)
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let png = pngData(fromTIFF: tiff),
           let size = pixelSize(of: png) {
            return PNGCapture(data: png, pixelWidth: size.width, pixelHeight: size.height)
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let png = pngData(from: image),
           let size = pixelSize(of: png) {
            return PNGCapture(data: png, pixelWidth: size.width, pixelHeight: size.height)
        }
        return nil
    }
    
    static func pngData(from image: NSImage) -> Data? {
        var rect = CGRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) {
                return png
            }
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
    
    static func pngData(fromTIFF tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
    
    static func hashPNG(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    
    static func hashFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return hashPNG(data)
    }
    
    static func pixelSize(of png: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, noCache),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
    
    static func pixelSize(at url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, noCache),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
    
    static func downsampledImage(at url: URL, maxPixel: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, noCache),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    
    static func thumbnail(at url: URL) -> NSImage? {
        downsampledImage(at: url, maxPixel: thumbnailMaxPixel)
    }
}
