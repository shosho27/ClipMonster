import Foundation

/// Security-scoped bookmarks for a user-chosen storage folder and for file
/// clips captured from the pasteboard. Required once the app is sandboxed.
enum ScopedBookmarks {
    private static let storageKey = "storageFolderBookmark"

    static func bookmark(for url: URL) -> Data? {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        let options: URL.BookmarkCreationOptions
        if Distribution.isSandboxed || Distribution.macAppStoreBuild {
            options = .withSecurityScope
        } else {
            options = []
        }
        return try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) -> URL? {
        var stale = false
        let sandboxOptions: URL.BookmarkResolutionOptions = (Distribution.isSandboxed || Distribution.macAppStoreBuild)
            ? [.withSecurityScope, .withoutUI]
            : [.withoutUI]
        if let url = try? URL(resolvingBookmarkData: data, options: sandboxOptions, relativeTo: nil, bookmarkDataIsStale: &stale) {
            return url
        }
        return try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    static func saveStorageFolder(_ url: URL) {
        if let data = bookmark(for: url) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func resolvedStorageFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        guard let url = resolve(data) else { return nil }
        if let refreshed = bookmark(for: url) {
            UserDefaults.standard.set(refreshed, forKey: storageKey)
        }
        return url
    }

    static func clearStorageFolder() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
