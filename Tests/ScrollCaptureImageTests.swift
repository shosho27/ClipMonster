import Cocoa
import ImageIO

@main
enum ScrollCaptureImageTests {
    static func main() throws {
        let width = 320, height = 500
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 35, y: 90, width: 190, height: 230))
        let original = context.makeImage()!
        let png = NSBitmapImageRep(cgImage: original).representation(using: .png, properties: [:])!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipmonster-decode-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try png.write(to: url)
        let decoded = ScrollCaptureImageDecoder.load(url)!
        // Delete the PNG before drawing, stitching, or exporting the CGImage.
        try FileManager.default.removeItem(at: url)
        let pixels = ScrollCaptureStitcher.Pixels(decoded)!
        precondition(pixels.bytes == ScrollCaptureStitcher.Pixels(original)!.bytes,
                     "Deleting the temporary screenshot lost its decoded pixels")
        let strips = [decoded, ScrollCaptureStitcher.bottomStrip(of: decoded, height: 120)!]
        let stitched = ScrollCaptureStitcher.compose(strips)!
        let image = NSImage(cgImage: stitched, size: NSSize(width: stitched.width, height: stitched.height))
        let exported = ImageStore.pngData(from: image)!
        let source = CGImageSourceCreateWithData(exported as CFData, nil)!
        let saved = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let savedPixels = ScrollCaptureStitcher.Pixels(saved)!
        precondition(saved.width == width && saved.height == height + 120)
        precondition(savedPixels.bytes == ScrollCaptureStitcher.Pixels(stitched)!.bytes,
                     "PNG export lost the stitched image")
        precondition(stride(from: 3, to: savedPixels.bytes.count, by: 4).allSatisfy { savedPixels.bytes[$0] == 255 },
                     "Saved output is unexpectedly transparent")
        print("PASS: temporary file deletion → decoded pixels → stitching → NSImage → exported PNG retains opaque content")
    }
}
