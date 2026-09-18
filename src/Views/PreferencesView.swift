import Cocoa
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var monitor: ClipboardMonitor
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
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
                
                prefSection("Paste") {
                    Toggle("Auto-paste into previous app", isOn: $monitor.autoPaste)
                    Text("After you pick an item, simulates ⌘V. Needs Accessibility.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
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
                    Text("Copies the newest screenshot's PNG path and pastes it into the focused app. Requires Accessibility; default: ⌘⇧V.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Text("Accessibility is required for the global shortcut and auto-paste.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                
                prefSection("Data Management") {
                    Button("Purge All Data") { monitor.purgeAll() }
                        .foregroundColor(.red)
                }
                
                // Extra space so last controls aren't tight against the footer
                Color.clear.frame(height: 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
