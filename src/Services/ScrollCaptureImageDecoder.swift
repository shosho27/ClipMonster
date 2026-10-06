import Foundation
import ImageIO

enum ScrollCaptureImageDecoder {
    /// The caller deletes this temporary PNG as soon as capture returns.
    /// ImageIO otherwise defers decoding until draw time, after the file is gone.
    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
