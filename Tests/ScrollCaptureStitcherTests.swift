import Cocoa

@main
enum ScrollCaptureStitcherTests {
    static func main() throws {
        func image(width: Int, height: Int, seed: UInt64 = 12345) -> CGImage {
            var state = seed
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for index in stride(from: 0, to: bytes.count, by: 4) {
                state = state &* 6364136223846793005 &+ 1
                bytes[index] = UInt8(truncatingIfNeeded: state >> 32)
                bytes[index + 1] = UInt8(truncatingIfNeeded: state >> 40)
                bytes[index + 2] = UInt8(truncatingIfNeeded: state >> 48)
            }
            let data = Data(bytes) as CFData
            return CGImage(width: width, height: height, bitsPerComponent: 8,
                           bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
        for scale in [1, 2] {
            let width = 320 * scale
            let height = 400 * scale
            let source = image(width: width, height: 1100 * scale)
            let first = source.cropping(to: CGRect(x: 0, y: 0, width: width, height: height))!
            var previous = first
            var strips = [first]
            var offset = 0
            // Typical steps followed by a smaller final scroll at the page bottom.
            for delta in [180 * scale, 180 * scale, 180 * scale, 160 * scale] {
                offset += delta
                let next = source.cropping(to: CGRect(x: 0, y: offset, width: width, height: height))!
                let result = ScrollCaptureStitcher.match(previous: .init(previous)!, next: .init(next)!)
                precondition(result == .moved(delta), "Incorrect match: \(result), expected \(delta)")
                strips.append(ScrollCaptureStitcher.bottomStrip(of: next, height: delta)!)
                previous = next
            }
            precondition(ScrollCaptureStitcher.match(previous: .init(previous)!, next: .init(previous)!) == .unchanged)
            let combined = ScrollCaptureStitcher.compose(strips)!
            precondition(combined.width == width && combined.height == 1100 * scale)
            precondition(ScrollCaptureStitcher.Pixels(combined)!.bytes == ScrollCaptureStitcher.Pixels(source)!.bytes,
                         "Composite differs from the original: seam or row ordering error")
            let unrelated = image(width: width, height: height, seed: 54321)
            precondition(ScrollCaptureStitcher.match(previous: .init(first)!, next: .init(unrelated)!) == .uncertain)
        }
        precondition(ScrollCaptureStitcher.compose([]) == nil)
        let small = image(width: 120, height: 80)
        let differentWidth = image(width: 121, height: 80)
        precondition(ScrollCaptureStitcher.match(previous: .init(small)!, next: .init(differentWidth)!) == .uncertain)
        precondition(ScrollCaptureStitcher.compose([small, differentWidth]) == nil)
        precondition(ScrollCaptureStitcher.bottomStrip(of: small, height: 0) == nil)
        precondition(ScrollCaptureStitcher.bottomStrip(of: small, height: 81) == nil)
        print("PASS: Retina/non-Retina offsets, final scroll, unchanged bottom, unrelated frames, exact stitched pixels, invalid dimensions")
    }
}
