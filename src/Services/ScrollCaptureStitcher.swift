import Cocoa

/// Compares overlapping viewports in pixel coordinates. No assumed relationship
/// between wheel distance, browser zoom, and Retina scale is needed.
enum ScrollCaptureStitcher {
    enum Match: Equatable {
        case unchanged
        case moved(Int)
        case uncertain
    }

    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            guard width > 0, height > 0,
                  let context = CGContext(data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = context.data else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
        }
    }

    static func match(previous: Pixels, next: Pixels) -> Match {
        guard previous.width == next.width, previous.height == next.height,
              previous.height >= 100 else { return .uncertain }
        let height = previous.height
        let margin = max(8, height / 20)
        // Sample the interior, avoiding scrollbars and small fixed edge elements.
        func error(shift: Int) -> Double {
            let usable = height - shift - margin * 2
            guard usable > 20 else { return .infinity }
            var total = 0
            for row in 0..<24 {
                let y = margin + row * (usable - 1) / 23
                for column in 0..<32 {
                    let x = previous.width / 10 + column * (previous.width * 8 / 10 - 1) / 31
                    let a = ((y + shift) * previous.width + x) * 4
                    let b = (y * next.width + x) * 4
                    for channel in 0..<3 {
                        total += min(50, abs(Int(previous.bytes[a + channel]) - Int(next.bytes[b + channel])))
                    }
                }
            }
            return Double(total) / Double(24 * 32 * 3)
        }
        let stationaryError = error(shift: 0)
        var bestShift = 0
        var bestError = stationaryError
        var scores = [Double]()
        for shift in 1...max(1, height * 3 / 4) {
            let score = error(shift: shift)
            scores.append(score)
            if score < bestError {
                bestError = score
                bestShift = shift
            }
        }
        if bestShift == 0 && stationaryError < 0.6 { return .unchanged }
        guard bestShift > 0, bestError < 3,
              stationaryError > bestError + 0.5 else { return .uncertain }
        // Repeated patterns can match multiple offsets. Do not silently corrupt
        // the capture by choosing one of several equally plausible seams.
        let alternate = scores.enumerated().filter { abs(($0.offset + 1) - bestShift) > 4 }
            .map(\.element).min() ?? .infinity
        guard alternate > bestError + 0.3 else { return .uncertain }
        return .moved(bestShift)
    }

    /// Copy a crop so it cannot retain the backing pixels of a whole viewport.
    static func bottomStrip(of image: CGImage, height: Int) -> CGImage? {
        guard height > 0, height <= image.height,
              let crop = image.cropping(to: CGRect(x: 0, y: image.height - height, width: image.width, height: height)),
              let context = CGContext(data: nil, width: image.width, height: height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: image.width, height: height))
        return context.makeImage()
    }

    /// Strips are retained rather than repeatedly allocating a growing bitmap.
    static func compose(_ strips: [CGImage]) -> CGImage? {
        guard let first = strips.first, strips.allSatisfy({ $0.width == first.width }) else { return nil }
        let height = strips.reduce(0) { $0 + $1.height }
        guard height > 0, first.width * height <= 60_000_000,
              let context = CGContext(data: nil, width: first.width, height: height,
                bitsPerComponent: 8, bytesPerRow: first.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var top = height
        for strip in strips {
            top -= strip.height
            context.draw(strip, in: CGRect(x: 0, y: top, width: strip.width, height: strip.height))
        }
        return context.makeImage()
    }
}
