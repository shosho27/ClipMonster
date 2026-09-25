import Foundation

/// Build-time and runtime switches for the Mac App Store edition versus the
/// direct (Developer ID / local) edition.
enum Distribution {
    #if MAS
    static let macAppStoreBuild = true
    #else
    static let macAppStoreBuild = false
    #endif

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Synthetic ⌘V is compiled out of Store binaries and also skipped when a
    /// direct build is running inside the App Sandbox.
    static var supportsAutoPaste: Bool {
        !macAppStoreBuild && !isSandboxed
    }

    static var supportsLaunchAgentFallback: Bool {
        !macAppStoreBuild && !isSandboxed
    }

    static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    }
}
