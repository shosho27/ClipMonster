import Cocoa
import SwiftUI

struct MarkupRequest: Identifiable {
    let id = UUID()
    let image: NSImage
    let onSaved: () -> Void
}

enum MarkupTool: String, CaseIterable, Identifiable {
    case select, pen, arrow, rectangle, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .rectangle: return "Box"
        case .text: return "Text"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        }
    }
}

struct MarkupPoint {
    let x: CGFloat
    let y: CGFloat
}

struct MarkupAnnotation: Identifiable {
    let id = UUID()
    let tool: MarkupTool
    var points: [MarkupPoint]
    var color: NSColor
    let lineWidth: CGFloat
    var text: String?
    var scale: CGFloat = 1
    var rotation: CGFloat = 0
}

enum MarkupGeometry {
    static func displayPoints(for annotation: MarkupAnnotation) -> [MarkupPoint] {
        let sourcePoints: [MarkupPoint]
        if annotation.tool == .rectangle, annotation.points.count > 1 {
            let first = annotation.points[0]
            let second = annotation.points[1]
            sourcePoints = [
                first,
                MarkupPoint(x: second.x, y: first.y),
                second,
                MarkupPoint(x: first.x, y: second.y)
            ]
        } else {
            sourcePoints = annotation.points
        }
        return transformed(sourcePoints, scale: annotation.scale, rotation: annotation.rotation)
    }

    static func transformed(_ points: [MarkupPoint], scale: CGFloat, rotation: CGFloat) -> [MarkupPoint] {
        guard let first = points.first else { return [] }
        let minX = points.map(\.x).min() ?? first.x
        let maxX = points.map(\.x).max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y
        let maxY = points.map(\.y).max() ?? first.y
        let center = MarkupPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let radians = rotation * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return points.map { point in
            let x = (point.x - center.x) * scale
            let y = (point.y - center.y) * scale
            return MarkupPoint(x: center.x + x * cosine - y * sine, y: center.y + x * sine + y * cosine)
        }
    }
}

struct MarkupEditorView: View {
    let image: NSImage
    @ObservedObject var monitor: ClipboardMonitor
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var annotations: [MarkupAnnotation] = []
    @State private var activePoints: [MarkupPoint] = []
    @State private var selectedAnnotationID: UUID? = nil
    @FocusState private var selectedTextIsFocused: Bool
    @State private var tool: MarkupTool = .pen
    @State private var color = Color.red
    @State private var lineWidth: CGFloat = 4
    @State private var textValue = "Text"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Annotate Capture", systemImage: "pencil.and.outline")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save Annotated Copy") { saveAnnotatedCopy() }
                    .buttonStyle(.borderedProminent)
                    .disabled(annotations.isEmpty)
            }
            .padding(14)

            Divider()

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(MarkupTool.allCases) { value in
                        MarkupToolButton(tool: value, isSelected: tool == value) {
                            tool = value
                        }
                    }
                }
                .padding(4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))

                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .labelsHidden()

                HStack(spacing: 4) {
                    Image(systemName: "lineweight")
                    Slider(value: $lineWidth, in: 1...14, step: 1)
                        .frame(width: 110)
                    Text("\(Int(lineWidth))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 18)
                }

                if tool == .text {
                    TextField("Text", text: $textValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 120, maxWidth: 220)
                }

                Spacer()

                Button(action: { _ = annotations.popLast() }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Undo last annotation")
                .disabled(annotations.isEmpty)
                Button(action: { annotations.removeAll() }) {
                    Image(systemName: "trash")
                }
                .help("Clear all annotations")
                .disabled(annotations.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let index = selectedIndex {
                Divider()
                HStack(spacing: 12) {
                    Label("Selected", systemImage: "cursorarrow.rays")
                        .font(.caption.weight(.semibold))
                    if annotations[index].tool == .text {
                        TextField("Text", text: selectedTextBinding(for: index))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 150, maxWidth: 250)
                            .focused($selectedTextIsFocused)
                    }
                    ColorPicker("Color", selection: selectedColorBinding(for: index), supportsOpacity: false)
                        .labelsHidden()
                        .help("Selected annotation color")
                    Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                    Slider(value: selectedScaleBinding(for: index), in: 0.25...3, step: 0.05)
                        .frame(width: 110)
                    Text("\(Int(annotations[index].scale * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 36)
                    Label("Rotate", systemImage: "rotate.right")
                        .font(.caption)
                    Slider(value: selectedRotationBinding(for: index), in: -180...180, step: 1)
                        .frame(width: 110)
                    Text("\(Int(annotations[index].rotation))°")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40)
                    Button(role: .destructive) {
                        annotations.remove(at: index)
                        selectedAnnotationID = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete selected annotation")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            Divider()

            GeometryReader { proxy in
                let size = fittedCanvasSize(in: proxy.size)
                ZStack {
                    Color(NSColor.windowBackgroundColor)
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: size.width, height: size.height)

                        MarkupCanvas(
                            annotations: annotations,
                            activePoints: activePoints,
                            activeTool: tool,
                            selectedAnnotationID: selectedAnnotationID,
                            activeColor: NSColor(color),
                            activeLineWidth: lineWidth,
                            activeText: textValue,
                            onChanged: { points in activePoints = points },
                            onSelect: { id in
                                selectedAnnotationID = id
                                selectedTextIsFocused = annotations.first(where: { $0.id == id })?.tool == .text
                            },
                            onMove: { id, points in
                                guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
                                annotations[index].points = points
                            },
                            onTransform: { id, scale, rotation in
                                guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
                                annotations[index].scale = scale
                                annotations[index].rotation = rotation
                            },
                            onArrowEndpoint: { id, endpoint, point in
                                guard let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].points.indices.contains(endpoint) else { return }
                                annotations[index].points[endpoint] = point
                                annotations[index].scale = 1
                                annotations[index].rotation = 0
                            },
                            onEnded: { points in
                                activePoints = []
                                guard tool != .select else { return }
                                let finalPoints = tool == .text ? Array(points.prefix(1)) : points
                                guard !finalPoints.isEmpty else { return }
                                if tool != .text && finalPoints.count < 2 { return }
                                annotations.append(MarkupAnnotation(
                                    tool: tool,
                                    points: finalPoints,
                                    color: NSColor(color),
                                    lineWidth: lineWidth,
                                    text: tool == .text ? textValue : nil
                                ))
                            }
                        )
                        .frame(width: size.width, height: size.height)
                    }
                    .shadow(radius: 4)
                }
            }
            .padding(16)

            Text(instructionText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 12)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return available }
        let scale = min(available.width / image.size.width, available.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func saveAnnotatedCopy() {
        guard let rendered = MarkupRenderer.render(image: image, annotations: annotations) else { return }
        _ = monitor.addAnnotatedImage(rendered)
        onSaved()
        dismiss()
    }

    private var selectedIndex: Int? {
        guard let selectedAnnotationID else { return nil }
        return annotations.firstIndex(where: { $0.id == selectedAnnotationID })
    }

    private func selectedColorBinding(for index: Int) -> Binding<Color> {
        Binding(get: { Color(nsColor: annotations[index].color) }, set: { annotations[index].color = NSColor($0) })
    }

    private func selectedTextBinding(for index: Int) -> Binding<String> {
        Binding(get: { annotations[index].text ?? "" }, set: { annotations[index].text = $0 })
    }

    private func selectedScaleBinding(for index: Int) -> Binding<CGFloat> {
        Binding(get: { annotations[index].scale }, set: { annotations[index].scale = $0 })
    }

    private func selectedRotationBinding(for index: Int) -> Binding<CGFloat> {
        Binding(get: { annotations[index].rotation }, set: { annotations[index].rotation = $0 })
    }

    private var instructionText: String {
        switch tool {
        case .select: return "Select selected — click an annotation, then drag it to a new position."
        case .pen: return "Pen selected — click and drag on the capture to draw."
        case .arrow: return "Arrow selected — drag from its tail to its tip."
        case .rectangle: return "Box selected — drag between opposite corners."
        case .text: return "Text selected — enter text above, then click where it belongs."
        }
    }
}

private struct MarkupToolButton: View {
    let tool: MarkupTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbol)
                .frame(width: 28, height: 26)
                .foregroundColor(isSelected ? .white : .primary)
                .background(isSelected ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .accessibilityLabel(tool.title)
    }
}

private struct MarkupCanvas: View {
    let annotations: [MarkupAnnotation]
    let activePoints: [MarkupPoint]
    let activeTool: MarkupTool
    let selectedAnnotationID: UUID?
    let activeColor: NSColor
    let activeLineWidth: CGFloat
    let activeText: String
    let onChanged: ([MarkupPoint]) -> Void
    let onSelect: (UUID?) -> Void
    let onMove: (UUID, [MarkupPoint]) -> Void
    let onTransform: (UUID, CGFloat, CGFloat) -> Void
    let onArrowEndpoint: (UUID, Int, MarkupPoint) -> Void
    let onEnded: ([MarkupPoint]) -> Void

    @State private var selectionDrag: SelectionDrag? = nil

    private struct SelectionDrag {
        let id: UUID
        let originalPoints: [MarkupPoint]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // A concrete transparent layer makes the full image rectangle hit-testable.
                Color.clear
                ForEach(annotations) { annotation in
                    MarkupAnnotationView(annotation: annotation, isSelected: annotation.id == selectedAnnotationID)
                }
                if !activePoints.isEmpty {
                    MarkupAnnotationView(annotation: MarkupAnnotation(
                        tool: activeTool,
                        points: activePoints,
                        color: activeColor,
                        lineWidth: activeLineWidth,
                        text: activeTool == .text ? activeText : nil
                    ))
                }
                if let selected = annotations.first(where: { $0.id == selectedAnnotationID }) {
                    MarkupSelectionHandles(
                        annotation: selected,
                        canvasSize: proxy.size,
                        onTransform: onTransform,
                        onArrowEndpoint: onArrowEndpoint
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = normalized(value.location, in: proxy.size)
                    switch activeTool {
                    case .select:
                        moveSelection(with: value, in: proxy.size)
                    case .pen:
                        var points = activePoints
                        if points.isEmpty { points = [point] }
                        else if distance(points.last!, point) > 0.002 { points.append(point) }
                        onChanged(points)
                    case .arrow, .rectangle:
                        onChanged([normalized(value.startLocation, in: proxy.size), point])
                    case .text:
                        onChanged([point])
                    }
                }
                .onEnded { value in
                    let point = normalized(value.location, in: proxy.size)
                    let points: [MarkupPoint]
                    switch activeTool {
                    case .select:
                        selectionDrag = nil
                        return
                    case .pen: points = activePoints.isEmpty ? [point] : activePoints
                    case .arrow, .rectangle: points = [normalized(value.startLocation, in: proxy.size), point]
                    case .text: points = [point]
                    }
                    onEnded(points)
                }
            )
        }
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> MarkupPoint {
        MarkupPoint(x: min(1, max(0, point.x / max(size.width, 1))), y: min(1, max(0, point.y / max(size.height, 1))))
    }

    private func distance(_ lhs: MarkupPoint, _ rhs: MarkupPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func moveSelection(with value: DragGesture.Value, in size: CGSize) {
        let start = normalized(value.startLocation, in: size)
        if selectionDrag == nil {
            guard let hit = hitTest(start) else {
                onSelect(nil)
                return
            }
            selectionDrag = SelectionDrag(id: hit.id, originalPoints: hit.points)
            onSelect(hit.id)
        }
        guard let selectionDrag else { return }
        let dx = value.translation.width / max(size.width, 1)
        let dy = value.translation.height / max(size.height, 1)
        let moved = selectionDrag.originalPoints.map {
            MarkupPoint(x: min(1, max(0, $0.x + dx)), y: min(1, max(0, $0.y + dy)))
        }
        onMove(selectionDrag.id, moved)
    }

    private func hitTest(_ point: MarkupPoint) -> MarkupAnnotation? {
        annotations.reversed().first { annotation in
            let points = MarkupGeometry.displayPoints(for: annotation)
            guard let first = points.first else { return false }
            switch annotation.tool {
            case .rectangle:
                guard points.count > 3 else { return false }
                let pad: CGFloat = 0.025
                let minX = (points.map(\.x).min() ?? first.x) - pad
                let maxX = (points.map(\.x).max() ?? first.x) + pad
                let minY = (points.map(\.y).min() ?? first.y) - pad
                let maxY = (points.map(\.y).max() ?? first.y) + pad
                return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
            case .text:
                return distance(first, point) < 0.20
            case .pen, .arrow:
                guard points.count > 1 else { return distance(first, point) < 0.04 }
                return zip(points, points.dropFirst()).contains { pointNearSegment(point, $0.0, $0.1) }
            case .select:
                return false
            }
        }
    }

    private func pointNearSegment(_ point: MarkupPoint, _ start: MarkupPoint, _ end: MarkupPoint) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, start) < 0.03 }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return distance(point, MarkupPoint(x: start.x + t * dx, y: start.y + t * dy)) < 0.035
    }
}

private struct MarkupAnnotationView: View {
    let annotation: MarkupAnnotation
    var isSelected = false

    var body: some View {
        GeometryReader { proxy in
            switch annotation.tool {
            case .text:
                if let point = annotation.points.first {
                    Text(annotation.text ?? "Text")
                        .font(.system(size: max(12, annotation.lineWidth * 5), weight: .bold))
                        .foregroundColor(Color(nsColor: annotation.color))
                        .scaleEffect(annotation.scale)
                        .rotationEffect(.degrees(annotation.rotation))
                        .padding(4)
                        .background(isSelected ? Color.accentColor.opacity(0.20) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isSelected ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                }
            case .pen, .arrow, .rectangle:
                ZStack {
                    annotationPath(in: proxy.size)
                        .stroke(Color(nsColor: annotation.color), style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round))
                    if isSelected {
                        annotationPath(in: proxy.size)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: annotation.lineWidth + 3, lineCap: .round, lineJoin: .round, dash: [5, 4]))
                    }
                }
            case .select:
                EmptyView()
            }
        }
    }

    private func annotationPath(in size: CGSize) -> Path {
        let points = MarkupGeometry.displayPoints(for: annotation)
            .map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var path = Path()
        guard let first = points.first else { return path }
        switch annotation.tool {
        case .select:
            break
        case .pen:
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        case .rectangle:
            guard points.count > 3 else { return path }
            path.move(to: points[0])
            path.addLine(to: points[1])
            path.addLine(to: points[2])
            path.addLine(to: points[3])
            path.closeSubpath()
        case .arrow:
            guard points.count > 1 else { return path }
            let end = points[1]
            path.move(to: first)
            path.addLine(to: end)
            let angle = atan2(end.y - first.y, end.x - first.x)
            let head = max(10, annotation.lineWidth * 3)
            for delta in [CGFloat.pi * 0.78, -CGFloat.pi * 0.78] {
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x + cos(angle + delta) * head, y: end.y + sin(angle + delta) * head))
            }
        case .text:
            break
        }
        return path
    }
}

private struct MarkupSelectionHandles: View {
    let annotation: MarkupAnnotation
    let canvasSize: CGSize
    let onTransform: (UUID, CGFloat, CGFloat) -> Void
    let onArrowEndpoint: (UUID, Int, MarkupPoint) -> Void

    private var points: [CGPoint] {
        MarkupGeometry.displayPoints(for: annotation)
            .map { CGPoint(x: $0.x * canvasSize.width, y: $0.y * canvasSize.height) }
    }

    private var bounds: CGRect {
        guard let first = points.first else { return .zero }
        if annotation.tool == .text {
            let font = NSFont.systemFont(ofSize: max(12, annotation.lineWidth * 5), weight: .bold)
            let textSize = (annotation.text ?? "Text").size(withAttributes: [.font: font])
            let width = max(24, textSize.width * annotation.scale + 16)
            let height = max(24, textSize.height * annotation.scale + 12)
            return CGRect(x: first.x - width / 2, y: first.y - height / 2, width: width, height: height)
        }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
            partial.union(CGRect(origin: point, size: .zero))
        }.insetBy(dx: -10, dy: -10)
    }

    var body: some View {
        ZStack {
            if annotation.tool == .arrow, points.count > 1 {
                EndpointHandle(point: points[0]) { point in onArrowEndpoint(annotation.id, 0, normalized(point)) }
                EndpointHandle(point: points[1]) { point in onArrowEndpoint(annotation.id, 1, normalized(point)) }
            } else {
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(width: max(18, bounds.width), height: max(18, bounds.height))
                    .position(x: bounds.midX, y: bounds.midY)

                let corners = [
                    CGPoint(x: bounds.minX, y: bounds.minY),
                    CGPoint(x: bounds.maxX, y: bounds.minY),
                    CGPoint(x: bounds.minX, y: bounds.maxY),
                    CGPoint(x: bounds.maxX, y: bounds.maxY)
                ]
                ForEach(corners.indices, id: \.self) { index in
                    ResizeHandle(point: corners[index], center: CGPoint(x: bounds.midX, y: bounds.midY), annotation: annotation, onTransform: onTransform)
                }

                RotationHandle(point: CGPoint(x: bounds.midX, y: bounds.minY - 28), center: CGPoint(x: bounds.midX, y: bounds.midY), annotation: annotation, onTransform: onTransform)
            }
        }
    }

    private func normalized(_ point: CGPoint) -> MarkupPoint {
        MarkupPoint(x: min(1, max(0, point.x / max(canvasSize.width, 1))), y: min(1, max(0, point.y / max(canvasSize.height, 1))))
    }
}

private struct EndpointHandle: View {
    let point: CGPoint
    let onMove: (CGPoint) -> Void

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .position(point)
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { onMove($0.location) })
    }
}

private struct ResizeHandle: View {
    let point: CGPoint
    let center: CGPoint
    let annotation: MarkupAnnotation
    let onTransform: (UUID, CGFloat, CGFloat) -> Void
    @State private var baseScale: CGFloat? = nil

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 14, height: 14)
            .overlay(Rectangle().stroke(.white, lineWidth: 1.5))
            .position(point)
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if baseScale == nil { baseScale = annotation.scale }
                    let start = max(1, hypot(value.startLocation.x - center.x, value.startLocation.y - center.y))
                    let current = max(1, hypot(value.location.x - center.x, value.location.y - center.y))
                    onTransform(annotation.id, min(3, max(0.25, (baseScale ?? annotation.scale) * current / start)), annotation.rotation)
                }
                .onEnded { _ in baseScale = nil }
            )
    }
}

private struct RotationHandle: View {
    let point: CGPoint
    let center: CGPoint
    let annotation: MarkupAnnotation
    let onTransform: (UUID, CGFloat, CGFloat) -> Void
    @State private var baseRotation: CGFloat? = nil

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .overlay(Image(systemName: "rotate.right").font(.system(size: 7)).foregroundColor(.white))
            .position(point)
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if baseRotation == nil { baseRotation = annotation.rotation }
                    let start = atan2(value.startLocation.y - center.y, value.startLocation.x - center.x)
                    let current = atan2(value.location.y - center.y, value.location.x - center.x)
                    let degrees = (current - start) * 180 / .pi
                    onTransform(annotation.id, annotation.scale, (baseRotation ?? annotation.rotation) + degrees)
                }
                .onEnded { _ in baseRotation = nil }
            )
    }
}
