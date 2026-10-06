import Cocoa

/// Accessibility hit testing happens off the UI thread with a bounded messaging
/// timeout. Only visible webpage/scroll-area bounds are eligible for capture.
enum CapturePageTarget {
    struct Region {
        let role: String
        let frame: CGRect
    }

    static func visibleFrame(ancestors: [Region], window: CGRect, screens: [CGRect], point: CGPoint) -> CGRect? {
        let areas = ancestors.filter { $0.role == kAXScrollAreaRole }
        let candidates = areas.isEmpty ? ancestors.filter { $0.role == "AXWebArea" } : areas
        for candidate in candidates {
            guard candidate.frame.contains(point) else { continue }
            for screen in screens where screen.contains(point) {
                let frame = candidate.frame.intersection(window).intersection(screen).integral
                if frame.width >= 200, frame.height >= 150 { return frame }
            }
        }
        return nil
    }

    static func resolve(point: CGPoint, pid: pid_t, screens: [CGRect]) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        var regions = [Region]()
        var windowFrame: CGRect?
        for _ in 0..<24 {
            AXUIElementSetMessagingTimeout(element, 0.25)
            if let role = attribute(element, kAXRoleAttribute) as? String, let frame = frame(element) {
                regions.append(Region(role: role, frame: frame))
                if role == kAXWindowRole { windowFrame = frame; break }
            }
            guard let parent = attribute(element, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        guard regions.contains(where: { $0.role == "AXWebArea" }), let windowFrame else { return nil }
        return visibleFrame(ancestors: regions, window: windowFrame, screens: screens, point: point)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
