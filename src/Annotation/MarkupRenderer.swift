import Cocoa

enum MarkupRenderer {
    static func render(image: NSImage, annotations: [MarkupAnnotation]) -> NSImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let output = NSImage(size: image.size)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        for annotation in annotations {
            draw(annotation, in: image.size)
        }
        output.unlockFocus()
        return output
    }

    private static func draw(_ annotation: MarkupAnnotation, in size: NSSize) {
        let points = MarkupGeometry.displayPoints(for: annotation)
            .map { NSPoint(x: $0.x * size.width, y: size.height - ($0.y * size.height)) }
        guard let first = points.first else { return }
        annotation.color.setStroke()
        annotation.color.setFill()

        switch annotation.tool {
        case .select:
            return
        case .pen:
            let path = NSBezierPath()
            path.lineWidth = annotation.lineWidth * annotation.scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: first)
            for point in points.dropFirst() { path.line(to: point) }
            path.stroke()
        case .rectangle:
            guard points.count > 3 else { return }
            let path = NSBezierPath()
            path.move(to: points[0])
            path.line(to: points[1])
            path.line(to: points[2])
            path.line(to: points[3])
            path.close()
            path.lineWidth = annotation.lineWidth * annotation.scale
            path.stroke()
        case .arrow:
            guard points.count > 1 else { return }
            let end = points[1]
            let path = NSBezierPath()
            path.lineWidth = annotation.lineWidth * annotation.scale
            path.lineCapStyle = .round
            path.move(to: first)
            path.line(to: end)
            let angle = atan2(end.y - first.y, end.x - first.x)
            let head = max(10, annotation.lineWidth * annotation.scale * 3)
            for delta in [CGFloat.pi * 0.78, -CGFloat.pi * 0.78] {
                path.move(to: end)
                path.line(to: NSPoint(x: end.x + cos(angle + delta) * head, y: end.y + sin(angle + delta) * head))
            }
            path.stroke()
        case .text:
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: annotation.color,
                .font: NSFont.systemFont(ofSize: max(12, annotation.lineWidth * 5), weight: .bold)
            ]
            NSGraphicsContext.current?.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: first.x, yBy: first.y)
            transform.rotate(byDegrees: annotation.rotation)
            transform.scale(by: annotation.scale)
            transform.concat()
            (annotation.text ?? "Text").draw(at: .zero, withAttributes: attributes)
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }
}
