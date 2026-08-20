import Cocoa

// MARK: - Drag session & temp cleanup
enum DragSession {
    static let began = Notification.Name("ClipMonsterDragBegan")
    static let ended = Notification.Name("ClipMonsterDragEnded")
    
    private static var active = false
    
    static func begin() {
        guard !active else { return }
        active = true
        NotificationCenter.default.post(name: began, object: nil)
        
        var globalMonitor: Any?
        var localMonitor: Any?
        
        let end: () -> Void = {
            guard active else { return }
            active = false
            if let g = globalMonitor {
                NSEvent.removeMonitor(g)
                globalMonitor = nil
            }
            if let l = localMonitor {
                NSEvent.removeMonitor(l)
                localMonitor = nil
            }
            NotificationCenter.default.post(name: ended, object: nil)
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            DispatchQueue.main.async { end() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            DispatchQueue.main.async { end() }
            return event
        }
    }
}

enum DragTempCleanup {
    /// Remove only ClipMonster 2.0 drag and preview PNGs from the temp directory.
    static func run() {
        let tmp = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for name in names {
            let isOurs = name.hasPrefix("clipmonster2-")
            guard isOurs, name.hasSuffix(".png") else { continue }
            let url = tmp.appendingPathComponent(name)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modified = attrs[.modificationDate] as? Date,
               modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

