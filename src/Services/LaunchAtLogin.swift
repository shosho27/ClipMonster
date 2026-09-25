import Cocoa
import ServiceManagement

enum LaunchAtLogin {
    static let label = "com.sashornock.ClipMonster2"

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled {
            return true
        }
        #if !MAS
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
        #else
        return false
        #endif
    }

    static func setEnabled(_ enabled: Bool) throws {
        do {
            try setLoginItem(enabled)
            #if !MAS
            removeLaunchAgent()
            #endif
            return
        } catch {
            #if MAS
            throw error
            #else
            if !enabled {
                removeLaunchAgent()
                if SMAppService.mainApp.status != .enabled { return }
            }
            try setLaunchAgent(enabled)
            #endif
        }
    }

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

    #if !MAS
    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
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
    #endif
}
