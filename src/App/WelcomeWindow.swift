import Cocoa
import SwiftUI

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static var shared: WelcomeWindowController?
    private static let seenKey = "hasSeenWelcome"

    static func showIfNeeded(onOpenPopover: @escaping () -> Void) {
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        let view = WelcomeView(
            onContinue: { markSeenAndClose() },
            onOpenPopover: {
                markSeenAndClose()
                onOpenPopover()
            }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to ClipMonster"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 460))
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        let controller = WelcomeWindowController(window: window)
        window.delegate = controller
        shared = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        if WelcomeWindowController.shared === self {
            WelcomeWindowController.shared = nil
        }
    }

    private static func markSeenAndClose() {
        UserDefaults.standard.set(true, forKey: seenKey)
        shared?.close()
        shared = nil
    }
}

struct WelcomeView: View {
    var onContinue: () -> Void
    var onOpenPopover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let artwork = NSImage(named: "Clipmonster") ?? bundleArtwork() {
                    Image(nsImage: artwork)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .cornerRadius(12)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("ClipMonster lives in the menu bar")
                        .font(.title2)
                        .bold()
                    Text("There is no Dock icon. Look at the right side of the menu bar.")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Copy text, a screenshot, or a file as usual. It appears in history.", systemImage: "doc.on.clipboard")
                Label("Open the board with the menu bar icon or \(shortcutLabel).", systemImage: "keyboard")
                #if MAS
                Label("Click a row to copy it, then press ⌘V in the app you want to paste into.", systemImage: "command")
                #else
                if Distribution.supportsAutoPaste {
                    Label("Click a row to copy and paste into the app you were using. Accessibility is optional and only needed for auto-paste.", systemImage: "accessibility")
                } else {
                    Label("Click a row to copy it, then press ⌘V in the app you want to paste into.", systemImage: "command")
                }
                #endif
                Label("History stays on this Mac. ClipMonster does not send clipboard data anywhere.", systemImage: "lock.shield")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack {
                Button("Open ClipMonster") { onOpenPopover() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Got it") { onContinue() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440, height: 460)
    }

    private var shortcutLabel: String {
        UserDefaults.standard.data(forKey: "customGlobalShortcut")
            .flatMap { try? JSONDecoder().decode(CustomShortcut.self, from: $0) }?
            .displayString ?? "⌃⌥V"
    }

    private func bundleArtwork() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "Clipmonster", withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
