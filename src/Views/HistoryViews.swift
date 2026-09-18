import Cocoa
import SwiftUI

struct HistoryListView: View {
    @ObservedObject var monitor: ClipboardMonitor
    let filtered: [ClipboardItem]
    @Binding var focusedIndex: Int
    var onActivate: (ClipboardItem) -> Void
    var onShowLargePreview: (ClipboardItem) -> Void
    var onOpenInPreview: (ClipboardItem) -> Void
    var onRevealInFinder: (ClipboardItem) -> Void
    var onCopyImagePath: (ClipboardItem) -> Void
    
    var body: some View {
        if monitor.history.isEmpty {
            VStack {
                Spacer()
                Image(systemName: "clipboard").font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 4)
                Text("No history yet.").foregroundColor(.secondary)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            VStack {
                Spacer()
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary).padding(.bottom, 4)
                Text("No matches.").foregroundColor(.secondary)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                    HistoryItemRow(
                        item: item,
                        monitor: monitor,
                        isFocused: index == focusedIndex,
                        onActivate: { onActivate(item) },
                        onShowLargePreview: { onShowLargePreview(item) },
                        onOpenInPreview: { onOpenInPreview(item) },
                        onRevealInFinder: { onRevealInFinder(item) },
                        onCopyImagePath: { onCopyImagePath(item) }
                    )
                    .listRowBackground(
                        index == focusedIndex
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
            }
        }
    }
}

struct HistoryItemRow: View {
    let item: ClipboardItem
    @ObservedObject var monitor: ClipboardMonitor
    var isFocused: Bool = false
    var onActivate: () -> Void
    var onShowLargePreview: () -> Void
    var onOpenInPreview: () -> Void
    var onRevealInFinder: () -> Void
    var onCopyImagePath: () -> Void
    
    @State private var showCheckmark = false
    
    private var canDrag: Bool {
        item.hasImage || item.fileURL != nil || item.text != nil
    }
    
    private var dragHelp: String {
        if item.hasImage {
            return "Click to copy · Double-click opens Preview · Space / eye for large preview"
        }
        if item.fileURL != nil {
            return "Click to copy · Double-click to open file · Drag to place"
        }
        return "Click to copy · Drag to place text"
    }
    
    var body: some View {
        let isSelected = monitor.selectedItems.contains(item.id)
        
        HStack(spacing: 4) {
            // Thumbnail (images only): click = large preview, double-click = Preview.app
            if item.hasImage {
                Group {
                    if let img = item.thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipped()
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .help("Click: large preview · Double-click: open in Preview")
                .onTapGesture(count: 2) { onOpenInPreview() }
                .onTapGesture(count: 1) { onShowLargePreview() }
                .onDrag {
                    DragSession.begin()
                    return item.makeDragItemProvider()
                } preview: {
                    dragPreview
                }
            }
            
            // Main row area: click = copy/paste, double-click = Preview for images/files
            HStack(spacing: 8) {
                if item.hasImage {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Image").font(.subheadline)
                        if item.isOCRing {
                            Text("OCR…").font(.caption).foregroundColor(.secondary)
                        } else if let ocr = item.ocrText, !ocr.isEmpty {
                            Text(ocr).lineLimit(2).font(.caption).foregroundColor(.secondary)
                        } else if item.pixelWidth > 0, item.pixelHeight > 0 {
                            Text("\(item.pixelWidth)×\(item.pixelHeight)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                } else if let url = item.fileURL {
                    Image(systemName: "doc").font(.title2).frame(width: 40)
                    Text(url.lastPathComponent).lineLimit(1)
                } else if let txt = item.text {
                    Text(txt).lineLimit(2).font(.system(.body, design: .monospaced))
                }
                Spacer()
                if showCheckmark {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).transition(.scale)
                } else if isSelected {
                    Image(systemName: "checkmark.square.fill").foregroundColor(.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help(dragHelp)
            .onTapGesture(count: 2) {
                if item.hasImage || item.fileURL != nil {
                    onOpenInPreview()
                }
            }
            .onTapGesture(count: 1) {
                if NSEvent.modifierFlags.contains(.shift) {
                    monitor.toggleSelection(for: item)
                } else {
                    onActivate()
                    withAnimation { showCheckmark = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation { showCheckmark = false }
                    }
                }
            }
            .onDrag {
                guard canDrag else { return NSItemProvider() }
                DragSession.begin()
                return item.makeDragItemProvider()
            } preview: {
                dragPreview
            }
            
            // Image actions: large preview, Preview.app, Finder, OCR, delete
            if item.hasImage {
                Button(action: { onShowLargePreview() }) {
                    Image(systemName: "eye")
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Large preview (Space)")
                
                Button(action: { onOpenInPreview() }) {
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Open in Preview")

                Button(action: { onRevealInFinder() }) {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Reveal image in Finder")

                Button(action: { onCopyImagePath() }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Copy image path")
                
                if item.isOCRing {
                    ProgressView().controlSize(.small).frame(width: 20)
                } else if let ocr = item.ocrText, !ocr.isEmpty {
                    Button(action: {
                        monitor.copyOCRText(for: item)
                        withAnimation { showCheckmark = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation { showCheckmark = false }
                        }
                    }) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.accentColor)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Copy OCR text")
                } else {
                    Button(action: { monitor.forceRunOCR(for: item.id) }) {
                        Image(systemName: "text.viewfinder")
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Extract text (OCR)")
                }
            }
            
            if !showCheckmark {
                Button(action: { monitor.deleteItem(item) }) {
                    Image(systemName: "xmark").foregroundColor(.secondary).padding(4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .padding(6)
        .background(
            isSelected ? Color.accentColor.opacity(0.15)
                : (isFocused ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .cornerRadius(6)
    }
    
    @ViewBuilder
    private var dragPreview: some View {
        if let img = item.thumbnail {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 160, maxHeight: 160)
                .cornerRadius(6)
                .shadow(radius: 4)
        } else if let url = item.fileURL {
            Label(url.lastPathComponent, systemImage: "doc")
                .padding(8)
                .background(.regularMaterial)
                .cornerRadius(6)
        } else if let txt = item.text {
            Text(txt)
                .lineLimit(3)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: 180, alignment: .leading)
                .background(.regularMaterial)
                .cornerRadius(6)
        } else {
            EmptyView()
        }
    }
}

