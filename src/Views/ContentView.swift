import Cocoa
import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: ClipboardMonitor
    var appDelegate: AppDelegate?
    @State private var showPreferences = false
    @State private var searchText = ""
    @State private var focusedIndex = 0
    /// In-popover large image preview (Space / eye button).
    @State private var largePreviewItem: ClipboardItem? = nil
    @State private var markupRequest: MarkupRequest? = nil
    @State private var confirmPurge = false
    @StateObject private var keyHandler = HistoryKeyHandler()
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Fixed header — always visible
                HStack {
                    Text(showPreferences ? "Preferences" : "ClipMonster 2.0").font(.headline)
                    Spacer()
                    if !showPreferences {
                        Button(action: { monitor.capturePaused.toggle() }) {
                            Image(systemName: monitor.capturePaused ? "play.circle.fill" : "pause.circle")
                        }
                        .buttonStyle(.plain)
                        .help(monitor.capturePaused ? "Resume capture" : "Pause capture")
                        .accessibilityLabel(monitor.capturePaused ? "Resume capture" : "Pause capture")
                        Spacer().frame(width: 8)
                        Button(action: { confirmPurge = true }) { Image(systemName: "trash") }
                            .buttonStyle(.plain).help("Purge All")
                            .accessibilityLabel("Purge all history")
                        Spacer().frame(width: 12)
                    }
                    if showPreferences {
                        Button("Done") { showPreferences = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Spacer().frame(width: 8)
                    }
                    Button(action: { showPreferences.toggle() }) {
                        Image(systemName: showPreferences ? "xmark.circle.fill" : "gearshape.fill")
                            .foregroundColor(showPreferences ? .secondary : .primary)
                    }.buttonStyle(.plain)
                    .help(showPreferences ? "Close preferences" : "Preferences")
                }.padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
                
                if !showPreferences {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search history…", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                Divider()
                
                // Flexible middle — scrolls when content is tall (esp. Preferences)
                Group {
                    if showPreferences {
                        PreferencesView(monitor: monitor)
                    } else {
                        VStack(spacing: 0) {
                            HistoryListView(
                                monitor: monitor,
                                filtered: monitor.filteredHistory(query: searchText),
                                focusedIndex: $focusedIndex,
                                onActivate: { item in activate(item) },
                                onShowLargePreview: { item in largePreviewItem = item },
                                onOpenInPreview: { item in _ = monitor.openInPreview(item) },
                                onRevealInFinder: { item in _ = monitor.revealInFinder(item) },
                                onCopyImagePath: { item in _ = monitor.copyImagePath(item) }
                            )
                            
                            if !monitor.selectedItems.isEmpty {
                                Divider()
                                Button(action: {
                                    monitor.copySelected()
                                    finishCopy()
                                }) {
                                    Text("Apply & Copy \(monitor.selectedItems.count) Items")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Fixed footer — Quit always reachable
                Divider()
                HStack {
                    if !showPreferences {
                        Text("↑↓ ⏎ · Space · 2× Preview · Esc · 1–9")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("Scroll for more settings")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Quit ClipMonster 2.0") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            }
            
            if let previewItem = largePreviewItem, previewItem.hasImage {
                LargeImagePreviewOverlay(
                    item: previewItem,
                    onOpenInPreview: {
                        _ = monitor.openInPreview(previewItem)
                    },
                    onAnnotate: {
                        guard let full = previewItem.loadFullImage() else { return }
                        largePreviewItem = nil
                        markupRequest = MarkupRequest(image: full) {
                            searchText = ""
                            focusedIndex = 0
                            largePreviewItem = nil
                        }
                    },
                    onDismiss: { largePreviewItem = nil }
                )
            }
        }
        .frame(width: 360, height: 540)
        .onAppear { bindKeyHandler(); keyHandler.install() }
        .onDisappear { keyHandler.remove() }
        .onChange(of: searchText) {
            focusedIndex = 0
            bindKeyHandler()
        }
        .onChange(of: showPreferences) {
            bindKeyHandler()
            if showPreferences {
                largePreviewItem = nil
                keyHandler.remove()
            } else {
                keyHandler.install()
            }
        }
        .onChange(of: focusedIndex) { bindKeyHandler() }
        .onChange(of: monitor.history.count) { bindKeyHandler() }
        .sheet(item: $markupRequest) { request in
            MarkupEditorView(image: request.image, monitor: monitor, onSaved: request.onSaved)
                .frame(minWidth: 760, minHeight: 620)
        }
        .alert("Purge all history?", isPresented: $confirmPurge) {
            Button("Purge", role: .destructive) { monitor.purgeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes captured text, screenshots, and files from ClipMonster's storage on this Mac.")
        }
    }
    
    private func bindKeyHandler() {
        keyHandler.showPreferences = { showPreferences }
        keyHandler.searchText = { searchText }
        keyHandler.setSearchText = { searchText = $0 }
        keyHandler.focusedIndex = { focusedIndex }
        keyHandler.setFocusedIndex = { focusedIndex = $0 }
        keyHandler.filtered = { monitor.filteredHistory(query: searchText) }
        keyHandler.activate = { activate($0) }
        keyHandler.previewFocused = { item in
            if largePreviewItem != nil {
                largePreviewItem = nil
                return
            }
            if item.hasImage {
                largePreviewItem = item
            } else if item.fileURL != nil {
                _ = monitor.openInPreview(item)
            }
        }
        keyHandler.isLargePreviewVisible = { largePreviewItem != nil }
        keyHandler.dismissLargePreview = { largePreviewItem = nil }
    }
    
    private func activate(_ item: ClipboardItem) {
        if NSEvent.modifierFlags.contains(.shift) {
            monitor.toggleSelection(for: item)
            return
        }
        monitor.copyToClipboard(item: item)
        finishCopy()
    }

    private func finishCopy() {
        #if MAS
        appDelegate?.handFocusBackAfterCopy()
        #else
        if Distribution.supportsAutoPaste, monitor.autoPaste {
            appDelegate?.autoPasteIntoPreviousApp()
        } else {
            appDelegate?.handFocusBackAfterCopy()
        }
        #endif
    }
}

/// In-popover preview. Decodes a ~720px downsample, not the full screenshot.
struct LargeImagePreviewOverlay: View {
    let item: ClipboardItem
    var onOpenInPreview: () -> Void
    var onAnnotate: () -> Void
    var onDismiss: () -> Void
    @State private var preview: NSImage?
    
    private var ocrPreview: String? { item.ocrText }
    private var displayImage: NSImage? { preview ?? item.thumbnail }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            VStack(spacing: 12) {
                if let image = displayImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 380)
                        .cornerRadius(8)
                        .shadow(radius: 12)
                }
                
                if let ocr = ocrPreview, !ocr.isEmpty {
                    Text(ocr)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                
                HStack(spacing: 12) {
                    Button("Annotate") {
                        onAnnotate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Open in Preview") {
                        onOpenInPreview()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("Close") { onDismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(16)
        }
        .transition(.opacity)
        .onAppear {
            if preview == nil {
                preview = item.previewImage()
            }
        }
        .onDisappear { preview = nil }
    }
}
