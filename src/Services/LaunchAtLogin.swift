import Cocoa
import ServiceManagement

// MARK: - Launch at Login
enum LaunchAtLogin {
    static let label = "com.sashornock.ClipMonster2"
    
    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    
    static var isEnabled: Bool {
        if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
            return true
        }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }
    
    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            do {
                try setLoginItem(enabled)
                removeLaunchAgent()
                return
            } catch {
                if !enabled {
                    removeLaunchAgent()
                    if !isEnabled { return }
                }
            }
        }
        try setLaunchAgent(enabled)
    }
    
    @available(macOS 13.0, *)
    private static func setLoginItem(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
    
    private static func setLaunchAgent(_ enabled: Bool) throws {
        if enabled {
            let appPath = Bundle.main.bundlePath
            guard appPath.hasSuffix(".app") else {
                throw NSError(
                    domain: "ClipMonster2",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Run the ClipMonster 2.0.app bundle so login launch can be configured."]
                )
            }
            
            let agentsDir = launchAgentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
            
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", appPath],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
        } else {
            removeLaunchAgent()
        }
    }
    
    private static func removeLaunchAgent() {
        try? FileManager.default.removeItem(at: launchAgentURL)
    }
}

