import Cocoa
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var showPrivacy = false
    @State private var confirmPurge = false
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                prefSection("Capture") {
                    Toggle(monitor.capturePaused ? "Capture paused" : "Pause capture", isOn: $monitor.capturePaused)
                    Text("While paused, new copies are not added to history.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                prefSection("History Limits") {
                    Toggle("Keep unlimited history", isOn: $monitor.unlimitedHistory)
                    Text("Stores every captured item until you delete or purge it. Disk space is the limit; only small thumbnails stay in memory.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !monitor.unlimitedHistory {
                        Stepper(value: $monitor.historyLimit, in: 10...500, step: 10) {
                            Text("Keep the last \(monitor.historyLimit) items")
                        }
                    }
                }
                
                #if !MAS
                if Distribution.supportsAutoPaste {
                    prefSection("Paste") {
                        Toggle("Auto-paste into previous app", isOn: $monitor.autoPaste)
                        Text("After you pick an item, simulates ⌘V. Needs Accessibility. Terminal receives a screenshot as its file path, because it cannot paste an image.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                #endif
                
                prefSection("OCR") {
                    Toggle("Auto-OCR new images", isOn: $monitor.autoOCR)
                    Text("Uses on-device Apple Vision. You can also OCR a single image from its row.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                prefSection("Global Shortcut") {
                    HStack {
                        Text("Show Popover:")
                        Spacer()
                        ShortcutRecorder(shortcut: $monitor.globalShortcut)
                    }
                    HStack {
                        Text("Paste latest image path:")
                        Spacer()
                        ShortcutRecorder(shortcut: $monitor.pathPasteShortcut)
                    }
                    #if MAS
                    Text("Copies the newest screenshot's PNG path to the clipboard. Press ⌘V in the focused app to insert it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    #else
                    Text(Distribution.supportsAutoPaste
                         ? "Copies the newest screenshot's PNG path and pastes it into the focused app. Requires Accessibility."
                         : "Copies the newest screenshot's PNG path to the clipboard. Press ⌘V in the focused app to insert it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    #endif
                    if let error = monitor.globalShortcutError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = monitor.pathPasteShortcutError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                prefSection("Startup") {
                    Toggle("Start ClipMonster at login", isOn: Binding(
                        get: { monitor.launchAtLogin },
                        set: { monitor.setLaunchAtLogin($0) }
                    ))
                    Text("Launches in the menu bar after you log in or reboot.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let err = monitor.launchAtLoginError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                prefSection("Persistence") {
                    Toggle("Keep history across reboots", isOn: $monitor.keepThroughReboot)
                    if monitor.keepThroughReboot {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Storage Location:").font(.caption).foregroundColor(.secondary)
                            HStack {
                                Text(monitor.storagePath.isEmpty ? "Default (App Support)" : monitor.storagePath)
                                    .lineLimit(1).truncationMode(.middle).font(.caption)
                                Spacer()
                                Button("Change...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.canCreateDirectories = true
                                    if panel.runModal() == .OK, let url = panel.url {
                                        monitor.changeStorageDirectory(to: url)
                                    }
                                }.controlSize(.mini)
                            }
                            if let error = monitor.storageError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                
                prefSection("Permissions") {
                    #if MAS
                    Text("This Mac App Store edition uses system hotkeys. Copy an item, then press ⌘V to paste. Accessibility is not required.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    #else
                    Text("Accessibility is required for auto-paste. Global shortcuts use system hotkeys.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    #endif
                }

                prefSection("Privacy") {
                    Text("Clipboard history stays on this Mac. ClipMonster does not send it anywhere.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Privacy Policy") { showPrivacy = true }
                        .controlSize(.mini)
                    Text("ClipMonster \(Distribution.versionString)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                prefSection("Data Management") {
                    Button("Purge All Data") { confirmPurge = true }
                        .foregroundColor(.red)
                }
                
                // Extra space so last controls aren't tight against the footer
                Color.clear.frame(height: 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Purge all history?", isPresented: $confirmPurge) {
            Button("Purge", role: .destructive) { monitor.purgeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes captured text, screenshots, and files from ClipMonster's storage on this Mac.")
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyPolicyView { showPrivacy = false }
        }
    }
    
    @ViewBuilder
    private func prefSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Divider()
    }
}
