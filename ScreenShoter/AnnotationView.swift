import SwiftUI
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Annotation model

struct DrawingItem: Identifiable {
    let id = UUID()
    var type: DrawingType
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    /// For .callout: number shown in circle (1, 2, 3…).
    var calloutNumber: Int?

    enum DrawingType: Hashable {
        case arrow
        case highlight
        case blur
        case rectangle
        case ellipse
        case freehand
        case callout
    }
}

struct TextItem: Identifiable {
    let id = UUID()
    var text: String
    /// Normalized [0,1] origin (top-left of text block).
    var position: CGPoint
    var fontSize: CGFloat
    var color: Color
}

enum AnnotationItem: Identifiable {
    case drawing(DrawingItem)
    case text(TextItem)

    var id: UUID {
        switch self {
        case .drawing(let d): return d.id
        case .text(let t): return t.id
        }
    }
}

private extension DrawingItem {
    func denormalized(to size: CGSize) -> DrawingItem {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        return copy
    }
}

private struct BlurRectsMask: Shape {
    var rects: [CGRect]
    func path(in _: CGRect) -> Path {
        var p = Path()
        for rect in rects where rect.width > 1 && rect.height > 1 {
            p.addRect(rect)
        }
        return p
    }
}

private let maxUndoSteps = 25

enum EditorTool: Hashable {
    case selection
    case arrow
    case highlight
    case blur
    case text
    case rectangle
    case ellipse
    case freehand
    case callout
}

struct AnnotationView: View {
    let image: NSImage
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var annotations: [AnnotationItem] = []
    @State private var currentTool: EditorTool = .arrow
    @State private var currentColor: Color = .green
    @State private var lineWidth: CGFloat = 4
    @State private var uploadToWebDAV = AppSettings.autoUploadToWebDAV
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var freehandPoints: [CGPoint] = []
    @State private var imageSize: CGSize = .zero
    @State private var isPinned = false
    @State private var selectedItemId: UUID?
    @State private var editingTextId: UUID?
    @State private var pendingTextAtPosition: CGPoint?
    @State private var undoStack: [[AnnotationItem]] = []
    @State private var redoStack: [[AnnotationItem]] = []
    @State private var calloutCounter: Int = 1
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                Divider()
                    .opacity(0.5)
                imageView
            }
            .background(.windowBackground)
        }
    }

    private func pushUndo() {
        let snapshot = annotations
        if undoStack.count >= maxUndoSteps { undoStack.removeFirst() }
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    private func performUndo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = last
        selectedItemId = nil
        editingTextId = nil
    }

    private func performRedo() {
        guard let last = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = last
        selectedItemId = nil
    }

    private var showColorAndStroke: Bool {
        switch currentTool {
        case .selection, .blur: return false
        case .arrow, .highlight, .text, .rectangle, .ellipse, .freehand, .callout: return true
        }
    }

    private func deleteSelected() {
        guard let id = selectedItemId else { return }
        pushUndo()
        annotations.removeAll { $0.id == id }
        selectedItemId = nil
        editingTextId = nil
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $currentTool) {
                Image(systemName: "cursorarrow").tag(EditorTool.selection)
                Image(systemName: "arrow.right").tag(EditorTool.arrow)
                Image(systemName: "square.dashed").tag(EditorTool.highlight)
                Image(systemName: "eye.slash").tag(EditorTool.blur)
                Image(systemName: "textformat").tag(EditorTool.text)
                Image(systemName: "rectangle").tag(EditorTool.rectangle)
                Image(systemName: "circle").tag(EditorTool.ellipse)
                Image(systemName: "pencil.tip").tag(EditorTool.freehand)
                Image(systemName: "number").tag(EditorTool.callout)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()
                .frame(height: 20)

            if showColorAndStroke {
                HStack(spacing: 8) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: currentColor == color ? 2 : 0))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                            .onTapGesture { currentColor = color }
                    }
                }
                Slider(value: $lineWidth, in: 2...12, step: 1)
                    .frame(width: 80)
            }

            Button { performUndo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("z", modifiers: .command)
            .disabled(undoStack.isEmpty)
            .help("annotation.undo")

            Button { performRedo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(redoStack.isEmpty)
            .help("annotation.redo")

            if selectedItemId != nil {
                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("annotation.delete")
            }

            Spacer()

            Toggle("annotation.upload_after_save", isOn: $uploadToWebDAV)
                .toggleStyle(.checkbox)

            Button { copyToClipboard() } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .help("annotation.copy")

            Button {
                Task {
                    let ok = await OCRService.recognizeAndCopyToClipboard(from: image)
                    await MainActor.run {
                        if !ok {
                            let alert = NSAlert()
                            alert.messageText = String(localized: "annotation.text_not_recognized")
                            alert.informativeText = String(localized: "annotation.ocr_failed")
                            alert.alertStyle = .informational
                            alert.runModal()
                        }
                    }
                }
            } label: {
                Image(systemName: "text.viewfinder")
            }
            .buttonStyle(.bordered)
            .help("annotation.ocr")

            Button { togglePin() } label: {
                Image(systemName: isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.bordered)
            .help(isPinned ? String(localized: "annotation.unpin") : String(localized: "annotation.pin"))

            Button("annotation.save") { save() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var imageView: some View {
        GeometryReader { geo in
            let scale = imageScale(in: geo.size)
            let viewSize = CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )
            let blurRects = blurRectsInView(viewSize: viewSize)
            let drawingItems = annotations.compactMap { item -> DrawingItem? in
                if case .drawing(let d) = item { return d }; return nil
            }
            let textItems = annotations.compactMap { item -> TextItem? in
                if case .text(let t) = item { return t }; return nil
            }

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: viewSize.width, height: viewSize.height)
                .overlay(
                    Group {
                        if !blurRects.isEmpty {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: viewSize.width, height: viewSize.height)
                                .blur(radius: 14)
                                .mask(BlurRectsMask(rects: blurRects))
                        }
                    }
                    .frame(width: viewSize.width, height: viewSize.height)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
                .padding(20)
                .overlay(
                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, _ in
                            for item in drawingItems {
                                drawItem(item.denormalized(to: viewSize), in: ctx, viewSize: viewSize, selectedId: selectedItemId)
                            }
                            if let start = dragStart, let current = dragCurrent, let dt = drawingTypeForCurrentTool() {
                                var preview = DrawingItem(type: dt, points: [start, current], color: currentColor, lineWidth: lineWidth, calloutNumber: nil)
                                if dt == .freehand, !freehandPoints.isEmpty {
                                    preview.points = freehandPoints
                                }
                                drawItem(preview, in: ctx, viewSize: viewSize, selectedId: nil)
                            }
                            if !freehandPoints.isEmpty, currentTool == .freehand {
                                var preview = DrawingItem(type: .freehand, points: freehandPoints, color: currentColor, lineWidth: lineWidth, calloutNumber: nil)
                                drawItem(preview, in: ctx, viewSize: viewSize, selectedId: nil)
                            }
                        }
                        .frame(width: viewSize.width, height: viewSize.height)
                        ForEach(textItems) { t in
                            let pos = CGPoint(x: t.position.x * viewSize.width, y: t.position.y * viewSize.height)
                            let isEditing = editingTextId == t.id
                            let isSelected = selectedItemId == t.id
                            textBlockView(text: t.text, fontSize: t.fontSize, color: t.color, at: pos, isSelected: isSelected, isEditing: isEditing, id: t.id, viewSize: viewSize)
                        }
                        ForEach(annotations.compactMap { item -> (id: UUID, center: CGPoint, num: Int)? in
                            if case .drawing(let d) = item, d.type == .callout, let first = d.points.first, let num = d.calloutNumber {
                                let denorm = d.denormalized(to: viewSize)
                                let center = denorm.points.first!
                                return (d.id, center, num)
                            }
                            return nil
                        }, id: \.id) { callout in
                            Text("\(callout.num)")
                                .font(.system(size: min(viewSize.width, viewSize.height) * 0.04, weight: .bold))
                                .foregroundColor(.white)
                                .position(callout.center)
                        }
                        if let pos = pendingTextAtPosition, viewSize.width > 0, viewSize.height > 0 {
                            textFieldOverlay(at: pos, viewSize: viewSize)
                        }
                    }
                    .frame(width: viewSize.width, height: viewSize.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: currentTool == .freehand ? 0 : 2, coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                let loc = value.location
                                switch currentTool {
                                case .selection:
                                    break
                                case .text, .callout:
                                    break
                                case .freehand:
                                    if dragStart == nil { dragStart = loc; freehandPoints = [loc] }
                                    freehandPoints.append(loc)
                                default:
                                    if dragStart == nil { dragStart = loc }
                                    dragCurrent = loc
                                }
                            }
                            .onEnded { value in
                                let endLoc = value.location
                                let dist = dragStart.map { hypot(endLoc.x - $0.x, endLoc.y - $0.y) } ?? 0
                                let isTap = dist < 5
                                if isTap && (currentTool == .selection || currentTool == .text || currentTool == .callout) {
                                    let norm = CGPoint(x: endLoc.x / viewSize.width, y: endLoc.y / viewSize.height)
                                    if currentTool == .selection {
                                        selectedItemId = hitTest(point: norm, viewSize: viewSize)
                                        editingTextId = nil
                                    } else if currentTool == .text {
                                        pendingTextAtPosition = endLoc
                                        pendingTextInput = ""
                                        selectedItemId = nil
                                    } else if currentTool == .callout {
                                        pushUndo()
                                        annotations.append(.drawing(DrawingItem(type: .callout, points: [norm], color: currentColor, lineWidth: lineWidth, calloutNumber: calloutCounter)))
                                        calloutCounter += 1
                                    }
                                    dragStart = nil; dragCurrent = nil
                                    return
                                }
                                if currentTool == .selection { dragStart = nil; dragCurrent = nil; return }
                                if currentTool == .text || currentTool == .callout { dragStart = nil; dragCurrent = nil; return }
                                if currentTool == .freehand {
                                    if freehandPoints.count >= 2, viewSize.width > 0, viewSize.height > 0 {
                                        let normalized = freehandPoints.map { CGPoint(x: $0.x / viewSize.width, y: $0.y / viewSize.height) }
                                        pushUndo()
                                        annotations.append(.drawing(DrawingItem(type: .freehand, points: normalized, color: currentColor, lineWidth: lineWidth, calloutNumber: nil)))
                                    }
                                    freehandPoints = []
                                    dragStart = nil
                                    dragCurrent = nil
                                    return
                                }
                                if let start = dragStart, viewSize.width > 0, viewSize.height > 0, let dt = drawingTypeForCurrentTool() {
                                    let nStart = CGPoint(x: start.x / viewSize.width, y: start.y / viewSize.height)
                                    let nEnd = CGPoint(x: value.location.x / viewSize.width, y: value.location.y / viewSize.height)
                                    var num: Int? = nil
                                    if dt == .callout { num = calloutCounter; calloutCounter += 1 }
                                    pushUndo()
                                    annotations.append(.drawing(DrawingItem(type: dt, points: [nStart, nEnd], color: currentColor, lineWidth: lineWidth, calloutNumber: num)))
                                }
                                dragStart = nil
                                dragCurrent = nil
                            }
                    )
                    .coordinateSpace(name: "canvas")
                )
                .overlay(alignment: .bottom) {
                    if currentTool == .blur {
                        Text(String(localized: "annotation.blur_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.bottom, 24)
                    }
                }
        }
        .onAppear { imageSize = CGSize(width: image.size.width, height: image.size.height) }
        .onKeyPress(.delete, action: { deleteSelected(); return .handled })
    }

    private func imageScale(in size: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(size.width / imageSize.width, size.height / imageSize.height)
    }

    private func blurRectsInView(viewSize: CGSize) -> [CGRect] {
        var rects: [CGRect] = []
        for item in annotations {
            guard case .drawing(let d) = item, d.type == .blur else { continue }
            let pts = d.points
            guard pts.count >= 2 else { continue }
            let r = CGRect(
                x: min(pts[0].x, pts[1].x) * viewSize.width,
                y: min(pts[0].y, pts[1].y) * viewSize.height,
                width: abs(pts[1].x - pts[0].x) * viewSize.width,
                height: abs(pts[1].y - pts[0].y) * viewSize.height
            )
            if r.width > 2, r.height > 2 { rects.append(r) }
        }
        if currentTool == .blur, let start = dragStart, let current = dragCurrent {
            let r = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            if r.width > 2, r.height > 2 { rects.append(r) }
        }
        return rects
    }

    private func drawingTypeForCurrentTool() -> DrawingItem.DrawingType? {
        switch currentTool {
        case .selection, .text: return nil
        case .arrow: return .arrow
        case .highlight: return .highlight
        case .blur: return .blur
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .freehand: return .freehand
        case .callout: return .callout
        }
    }

    private func hitTest(point norm: CGPoint, viewSize: CGSize) -> UUID? {
        let hitRadiusNorm: CGFloat = 0.02
        for item in annotations.reversed() {
            switch item {
            case .drawing(let d):
                if hitTestDrawing(d, point: norm, hitRadius: hitRadiusNorm) {
                    return d.id
                }
            case .text(let t):
                let estSize = textSizeEstimate(t.text, fontSize: t.fontSize)
                let rNorm = CGRect(x: t.position.x, y: t.position.y, width: estSize.width / viewSize.width, height: estSize.height / viewSize.height)
                if rNorm.contains(norm) { return t.id }
            }
        }
        return nil
    }

    private func textSizeEstimate(_ text: String, fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: size.width + 8, height: size.height + 6)
    }

    private func hitTestDrawing(_ item: DrawingItem, point norm: CGPoint, hitRadius: CGFloat) -> Bool {
        let pts = item.points
        switch item.type {
        case .arrow:
            guard pts.count >= 2 else { return false }
            return distanceFromPointToSegment(norm, p0: pts[0], p1: pts[1]) < hitRadius
        case .highlight, .blur, .rectangle, .ellipse:
            guard pts.count >= 2 else { return false }
            let r = CGRect(
                x: min(pts[0].x, pts[1].x),
                y: min(pts[0].y, pts[1].y),
                width: abs(pts[1].x - pts[0].x),
                height: abs(pts[1].y - pts[0].y)
            )
            return r.contains(norm)
        case .freehand:
            guard pts.count >= 2 else { return false }
            for i in 0..<(pts.count - 1) {
                if distanceFromPointToSegment(norm, p0: pts[i], p1: pts[i+1]) < hitRadius { return true }
            }
            return false
        case .callout:
            guard let first = pts.first else { return false }
            let radius: CGFloat = 0.04
            return hypot(norm.x - first.x, norm.y - first.y) < radius
        }
    }

    private func distanceFromPointToSegment(_ p: CGPoint, p0: CGPoint, p1: CGPoint) -> CGFloat {
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return hypot(p.x - p0.x, p.y - p0.y) }
        var t = ((p.x - p0.x) * dx + (p.y - p0.y) * dy) / len2
        t = max(0, min(1, t))
        let proj = CGPoint(x: p0.x + t * dx, y: p0.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    @ViewBuilder
    private func textBlockView(text: String, fontSize: CGFloat, color: Color, at pos: CGPoint, isSelected: Bool, isEditing: Bool, id: UUID, viewSize: CGSize) -> some View {
        Group {
            if isEditing {
                TextField("", text: bindingForTextItem(id: id), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize))
                    .foregroundColor(color)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2))
                    .lineLimit(1...10)
            } else {
                Text(text)
                    .font(.system(size: fontSize))
                    .foregroundColor(color)
                    .padding(4)
                    .fixedSize(horizontal: true, vertical: true)
                    .overlay(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                    .padding(2)
                            }
                        }
                    )
                    .onTapGesture {
                        if currentTool == .selection && selectedItemId == id {
                            editingTextId = id
                        }
                    }
            }
        }
        .position(pos)
    }

    private func bindingForTextItem(id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let idx = annotations.firstIndex(where: { if case .text(let t) = $0 { return t.id == id }; return false }),
                      case .text(let t) = annotations[idx] else { return "" }
                return t.text
            },
            set: { newValue in
                guard let idx = annotations.firstIndex(where: { if case .text(let t) = $0 { return t.id == id }; return false }),
                      case .text(var t) = annotations[idx] else { return }
                t.text = newValue
                annotations[idx] = .text(t)
            }
        )
    }

    @State private var pendingTextInput: String = ""

    @ViewBuilder
    private func textFieldOverlay(at pos: CGPoint, viewSize: CGSize) -> some View {
        TextField("annotation.text_placeholder", text: $pendingTextInput)
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .padding(8)
            .background(Color.primary.opacity(0.08))
            .frame(width: 160, alignment: .leading)
            .onSubmit {
                commitPendingText(at: pos, viewSize: viewSize)
            }
            .position(x: pos.x + 80, y: pos.y + 12)
    }

    private func commitPendingText(at pos: CGPoint, viewSize: CGSize) {
        let text = pendingTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let textToAdd = text.isEmpty ? " " : text
        let norm = CGPoint(x: pos.x / viewSize.width, y: pos.y / viewSize.height)
        pushUndo()
        annotations.append(.text(TextItem(text: textToAdd, position: norm, fontSize: 16, color: currentColor)))
        pendingTextAtPosition = nil
        pendingTextInput = ""
    }

    private func drawItem(_ item: DrawingItem, in ctx: GraphicsContext, viewSize: CGSize, selectedId: UUID?) {
        let pts = item.points
        let sw = item.lineWidth
        let c = item.color
        let selected = item.id == selectedId

        switch item.type {
        case .arrow:
            guard pts.count >= 2 else { return }
            var path = Path()
            path.move(to: pts[0])
            path.addLine(to: pts[1])
            ctx.stroke(path, with: .color(c), lineWidth: sw)
            let angle = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x)
            let size: CGFloat = sw * 3
            var head = Path()
            head.move(to: pts[1])
            head.addLine(to: CGPoint(x: pts[1].x - size * cos(angle - .pi/6), y: pts[1].y - size * sin(angle - .pi/6)))
            head.addLine(to: CGPoint(x: pts[1].x - size * cos(angle + .pi/6), y: pts[1].y - size * sin(angle + .pi/6)))
            head.closeSubpath()
            ctx.fill(head, with: .color(c))

        case .highlight, .rectangle:
            guard pts.count >= 2 else { return }
            let rect = CGRect(
                x: min(pts[0].x, pts[1].x),
                y: min(pts[0].y, pts[1].y),
                width: abs(pts[1].x - pts[0].x),
                height: abs(pts[1].y - pts[0].y)
            )
            if rect.width > 2, rect.height > 2 {
                let path = Path(rect)
                if item.type == .highlight {
                    ctx.fill(path, with: .color(c.opacity(0.25)))
                }
                ctx.stroke(path, with: .color(c), lineWidth: sw)
            }

        case .ellipse:
            guard pts.count >= 2 else { return }
            let rect = CGRect(
                x: min(pts[0].x, pts[1].x),
                y: min(pts[0].y, pts[1].y),
                width: abs(pts[1].x - pts[0].x),
                height: abs(pts[1].y - pts[0].y)
            )
            if rect.width > 2, rect.height > 2 {
                let path = Path(ellipseIn: rect)
                ctx.stroke(path, with: .color(c), lineWidth: sw)
            }

        case .blur:
            guard pts.count >= 2 else { return }
            let rect = CGRect(
                x: min(pts[0].x, pts[1].x),
                y: min(pts[0].y, pts[1].y),
                width: abs(pts[1].x - pts[0].x),
                height: abs(pts[1].y - pts[0].y)
            )
            if rect.width > 2, rect.height > 2 {
                let path = Path(rect)
                ctx.stroke(path, with: .color(.gray.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

        case .freehand:
            guard pts.count >= 2 else { return }
            var path = Path()
            path.move(to: pts[0])
            for i in 1..<pts.count { path.addLine(to: pts[i]) }
            ctx.stroke(path, with: .color(c), lineWidth: sw)

        case .callout:
            guard let first = pts.first, item.calloutNumber != nil else { return }
            let radius: CGFloat = min(viewSize.width, viewSize.height) * 0.04
            let circle = Path(ellipseIn: CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2))
            ctx.fill(circle, with: .color(c))
            ctx.stroke(circle, with: .color(.white), lineWidth: 2)
        }

        if selected {
            let selRect: CGRect
            switch item.type {
            case .arrow:
                guard pts.count >= 2 else { return }
                selRect = CGRect(x: min(pts[0].x, pts[1].x) - 4, y: min(pts[0].y, pts[1].y) - 4, width: abs(pts[1].x - pts[0].x) + 8, height: abs(pts[1].y - pts[0].y) + 8)
            case .highlight, .blur, .rectangle, .ellipse:
                guard pts.count >= 2 else { return }
                selRect = CGRect(x: min(pts[0].x, pts[1].x) - 3, y: min(pts[0].y, pts[1].y) - 3, width: abs(pts[1].x - pts[0].x) + 6, height: abs(pts[1].y - pts[0].y) + 6)
            case .freehand:
                guard !pts.isEmpty else { return }
                let minX = pts.map(\.x).min()! - 4
                let minY = pts.map(\.y).min()! - 4
                let maxX = pts.map(\.x).max()! + 4
                let maxY = pts.map(\.y).max()! + 4
                selRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            case .callout:
                guard let first = pts.first else { return }
                let r = min(viewSize.width, viewSize.height) * 0.045
                selRect = CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2)
            }
            let path = Path(selRect)
            ctx.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }

    /// Рендер текущего изображения с аннотациями и обоинами в Data (PNG/JPEG). Учитывает «Уменьшать Retina».
    private func renderedImageData() -> Data? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let scrW = Int(image.size.width * scale)
        let scrH = Int(image.size.height * scale)
        guard scrW > 0, scrH > 0 else { return nil }
        var outW = scrW
        var outH = scrH
        var drawScreenshotRect = NSRect(x: 0, y: 0, width: CGFloat(scrW), height: CGFloat(scrH))
        var wallpaperImage: NSImage?

        if let preset = AppSettings.wallpaperPreset, preset != .none {
            let wallSize = CGSize(width: CGFloat(outW) / scale, height: CGFloat(outH) / scale)
            if let wall = WallpaperPresetHelper.image(for: preset, size: wallSize, scale: scale) {
                wallpaperImage = wall
                let paddingHPt = AppSettings.wallpaperPaddingPreset.points
                let paddingVPt = AppSettings.wallpaperPaddingVerticalPreset.points
                let paddingHPx = paddingHPt * scale
                let paddingVPx = paddingVPt * scale
                let insetW = CGFloat(outW) - 2 * paddingHPx
                let insetH = CGFloat(outH) - 2 * paddingVPx
                if insetW > 0, insetH > 0 {
                    let scaleS = min(insetW / CGFloat(scrW), insetH / CGFloat(scrH))
                    let sw = Int(CGFloat(scrW) * scaleS)
                    let sh = Int(CGFloat(scrH) * scaleS)
                    let x = (outW - sw) / 2
                    let y = (outH - sh) / 2
                    drawScreenshotRect = NSRect(x: x, y: y, width: sw, height: sh)
                }
            }
        } else {
            let wallpaperPath: String? = AppSettings.useMacWallpaper
                ? MacWallpaperHelper.currentWallpaperImagePath()
                : AppSettings.wallpaperImagePath
            if let path = wallpaperPath, !path.isEmpty,
               let wall = NSImage(contentsOfFile: path) {
                let wallSize = wall.size
                outW = Int(wallSize.width * scale)
                outH = Int(wallSize.height * scale)
                let paddingHPt = AppSettings.wallpaperPaddingPreset.points
                let paddingVPt = AppSettings.wallpaperPaddingVerticalPreset.points
                let paddingHPx = paddingHPt * scale
                let paddingVPx = paddingVPt * scale
                let insetW = CGFloat(outW) - 2 * paddingHPx
                let insetH = CGFloat(outH) - 2 * paddingVPx
                if insetW > 0, insetH > 0 {
                    wallpaperImage = wall
                    let scaleS = min(insetW / CGFloat(scrW), insetH / CGFloat(scrH))
                    let sw = Int(CGFloat(scrW) * scaleS)
                    let sh = Int(CGFloat(scrH) * scaleS)
                    let x = (outW - sw) / 2
                    let y = (outH - sh) / 2
                    drawScreenshotRect = NSRect(x: x, y: y, width: sw, height: sh)
                }
            }
        }

        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: outW, pixelsHigh: outH, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high

        if let wall = wallpaperImage, let ctx = NSGraphicsContext.current?.cgContext {
            // Bitmap: origin внизу слева. Рисуем обои с rect с отрицательной высотой — верх картинки к верху bitmap
            if let cgImage = wall.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let r = CGRect(x: 0, y: CGFloat(outH), width: CGFloat(outW), height: -CGFloat(outH))
                ctx.draw(cgImage, in: r)
            } else {
                ctx.saveGState()
                ctx.translateBy(x: 0, y: CGFloat(outH))
                ctx.scaleBy(x: 1, y: -1)
                wall.draw(in: NSRect(x: 0, y: 0, width: outW, height: outH))
                ctx.restoreGState()
            }
        }

        image.draw(in: drawScreenshotRect)

        let drawScaleX = drawScreenshotRect.width / CGFloat(scrW)
        let drawScaleY = drawScreenshotRect.height / CGFloat(scrH)
        let drawOffsetX = drawScreenshotRect.origin.x
        let drawOffsetY = drawScreenshotRect.origin.y

        // Рисуем стрелки, подсветки, прямоугольники, эллипсы, свободные линии, callouts
        for item in annotations {
            guard case .drawing(let d) = item else { continue }
            let pts: [CGPoint] = d.points.map {
                CGPoint(
                    x: drawOffsetX + $0.x * drawScreenshotRect.width,
                    y: drawOffsetY + drawScreenshotRect.height - $0.y * drawScreenshotRect.height
                )
            }
            let c = NSColor(d.color)
            let sw = d.lineWidth * scale * min(drawScaleX, drawScaleY)

            switch d.type {
            case .arrow:
                guard pts.count >= 2 else { continue }
                let path = NSBezierPath()
                path.move(to: pts[0])
                path.line(to: pts[1])
                path.lineWidth = sw
                c.setStroke()
                path.stroke()
                let angle = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x)
                let size = sw * 3
                let head = NSBezierPath()
                head.move(to: pts[1])
                head.line(to: CGPoint(x: pts[1].x - size * cos(angle - .pi/6), y: pts[1].y - size * sin(angle - .pi/6)))
                head.line(to: CGPoint(x: pts[1].x - size * cos(angle + .pi/6), y: pts[1].y - size * sin(angle + .pi/6)))
                head.close()
                c.setFill()
                head.fill()

            case .highlight, .rectangle:
                guard pts.count >= 2 else { continue }
                let rect = NSRect(
                    x: min(pts[0].x, pts[1].x),
                    y: min(pts[0].y, pts[1].y),
                    width: abs(pts[1].x - pts[0].x),
                    height: abs(pts[1].y - pts[0].y)
                )
                if rect.width > 2, rect.height > 2 {
                    if d.type == .highlight {
                        c.withAlphaComponent(0.25).setFill()
                        NSBezierPath(rect: rect).fill()
                    }
                    c.setStroke()
                    let bp = NSBezierPath(rect: rect)
                    bp.lineWidth = sw
                    bp.stroke()
                }

            case .ellipse:
                guard pts.count >= 2 else { continue }
                let rect = NSRect(
                    x: min(pts[0].x, pts[1].x),
                    y: min(pts[0].y, pts[1].y),
                    width: abs(pts[1].x - pts[0].x),
                    height: abs(pts[1].y - pts[0].y)
                )
                if rect.width > 2, rect.height > 2 {
                    c.setStroke()
                    let bp = NSBezierPath(ovalIn: rect)
                    bp.lineWidth = sw
                    bp.stroke()
                }

            case .freehand:
                guard pts.count >= 2 else { continue }
                let path = NSBezierPath()
                path.move(to: pts[0])
                for i in 1..<pts.count { path.line(to: pts[i]) }
                c.setStroke()
                path.lineWidth = sw
                path.stroke()

            case .callout:
                guard let first = pts.first, let num = d.calloutNumber else { continue }
                let radius = min(drawScreenshotRect.width, drawScreenshotRect.height) * 0.04
                let circleRect = NSRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2)
                c.setFill()
                NSBezierPath(ovalIn: circleRect).fill()
                NSColor.white.setStroke()
                let strokePath = NSBezierPath(ovalIn: circleRect)
                strokePath.lineWidth = 2
                strokePath.stroke()
                let numStr = "\(num)"
                let font = NSFont.boldSystemFont(ofSize: radius * 1.2)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                let size = numStr.size(withAttributes: attrs)
                let textRect = NSRect(x: first.x - size.width/2, y: first.y - size.height/2, width: size.width, height: size.height)
                numStr.draw(in: textRect, withAttributes: attrs)

            case .blur:
                break
            }
        }

        // Текстовые аннотации
        for item in annotations {
            guard case .text(let t) = item else { continue }
            let pt = CGPoint(
                x: drawOffsetX + t.position.x * drawScreenshotRect.width,
                y: drawOffsetY + drawScreenshotRect.height - t.position.y * drawScreenshotRect.height
            )
            let font = NSFont.systemFont(ofSize: t.fontSize * scale * min(drawScaleX, drawScaleY))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(t.color)]
            let size = t.text.size(withAttributes: attrs)
            let textRect = NSRect(x: pt.x, y: pt.y - size.height, width: size.width + 8, height: size.height + 6)
            t.text.draw(in: textRect, withAttributes: attrs)
        }

        // Размытие: собираем итог в Core Image и один раз рендерим в bitmap (обход проблем с отрисовкой в контекст)
        NSGraphicsContext.current?.flushGraphics()

        var baseCGImage = bitmap.cgImage
        if baseCGImage == nil {
            let nsImg = NSImage(size: NSSize(width: outW, height: outH))
            nsImg.addRepresentation(bitmap)
            var proposedRect = NSRect(x: 0, y: 0, width: outW, height: outH)
            baseCGImage = nsImg.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        }

        if let base = baseCGImage {
            let ciContext = CIContext(options: [.useSoftwareRenderer: false])
            var resultImage = CIImage(cgImage: base)
            let boundsCI = CGRect(x: 0, y: 0, width: outW, height: outH)

            for item in annotations {
                guard case .drawing(let d) = item, d.type == .blur else { continue }
                let pts: [CGPoint] = d.points.map {
                    CGPoint(
                        x: drawOffsetX + $0.x * drawScreenshotRect.width,
                        y: drawOffsetY + drawScreenshotRect.height - $0.y * drawScreenshotRect.height
                    )
                }
                guard pts.count >= 2 else { continue }
                var rect = CGRect(
                    x: min(pts[0].x, pts[1].x),
                    y: min(pts[0].y, pts[1].y),
                    width: abs(pts[1].x - pts[0].x),
                    height: abs(pts[1].y - pts[0].y)
                )
                rect.origin.x = max(0, min(rect.minX, boundsCI.maxX - rect.width))
                rect.origin.y = max(0, min(rect.minY, boundsCI.maxY - rect.height))
                rect.size.width = min(rect.width, boundsCI.maxX - rect.minX)
                rect.size.height = min(rect.height, boundsCI.maxY - rect.minY)
                guard rect.width > 2, rect.height > 2 else { continue }

                let cropped = resultImage.cropped(to: rect)
                let blurFilter = CIFilter.gaussianBlur()
                blurFilter.setValue(cropped, forKey: kCIInputImageKey)
                blurFilter.setValue(28, forKey: kCIInputRadiusKey)
                guard let blurred = blurFilter.outputImage else { continue }
                let blurredExtent = blurred.extent
                let patchRect = CGRect(
                    x: blurredExtent.minX + max(0, (blurredExtent.width - rect.width) / 2),
                    y: blurredExtent.minY + max(0, (blurredExtent.height - rect.height) / 2),
                    width: min(rect.width, blurredExtent.width),
                    height: min(rect.height, blurredExtent.height)
                )
                guard patchRect.width > 0, patchRect.height > 0 else { continue }
                let blurredPatch = blurred.cropped(to: patchRect)
                let patchAtOrigin = blurredPatch.transformed(by: CGAffineTransform(translationX: rect.minX - patchRect.minX, y: rect.minY - patchRect.minY))

                guard let composite = CIFilter(name: "CISourceOverCompositing") else { continue }
                composite.setValue(patchAtOrigin, forKey: kCIInputImageKey)
                composite.setValue(resultImage, forKey: kCIInputBackgroundImageKey)
                guard let composited = composite.outputImage else { continue }
                resultImage = composited
            }

            if let finalCGImage = ciContext.createCGImage(resultImage, from: boundsCI),
               let bitmapCtx = NSGraphicsContext(bitmapImageRep: bitmap) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = bitmapCtx
                bitmapCtx.cgContext.draw(finalCGImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        NSGraphicsContext.current?.flushGraphics()

        NSGraphicsContext.restoreGraphicsState()

        var finalBitmap = bitmap
        if AppSettings.scaleDownRetina, outW >= 2, outH >= 2 {
            let smallW = outW / 2
            let smallH = outH / 2
            if let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: smallW, pixelsHigh: smallH, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
                NSGraphicsContext.current?.imageInterpolation = .high
                bitmap.draw(in: NSRect(x: 0, y: 0, width: smallW, height: smallH))
                NSGraphicsContext.restoreGraphicsState()
                finalBitmap = small
            }
        }

        let format = AppSettings.screenshotFormat
        if format == .jpeg {
            return finalBitmap.representation(using: .jpeg, properties: [.compressionFactor: AppSettings.compressionLevel.jpegQuality])
        }
        return finalBitmap.representation(using: .png, properties: [:])
    }

    private func copyToClipboard() {
        guard let data = renderedImageData() else { return }
        let format = AppSettings.screenshotFormat
        let type: NSPasteboard.PasteboardType = format == .jpeg ? NSPasteboard.PasteboardType("public.jpeg") : .png
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: type)
    }

    private func copyLinkToClipboard(_ link: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        if let url = URL(string: link) {
            NSPasteboard.general.writeObjects([url as NSURL])
        }
    }

    private func closeAnnotationWindow() {
        DispatchQueue.main.async {
            WindowDockHelper.window(for: .annotation)?.close()
        }
    }

    private func togglePin() {
        guard let window = WindowDockHelper.window(for: .annotation) else { return }
        isPinned.toggle()
        if isPinned {
            window.level = .floating
            window.collectionBehavior = [.fullScreenAuxiliary]
        } else {
            window.level = .normal
            window.collectionBehavior = [.managed, .participatesInCycle]
        }
    }

    private func save() {
        guard let fileData = renderedImageData() else { return }
        let format = AppSettings.screenshotFormat
        let ext = format.fileExtension

        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .jpeg ? [.jpeg] : [.png]
        panel.nameFieldStringValue = "screenshot_\(ISO8601DateFormatter().string(from: Date()).prefix(19).replacingOccurrences(of: ":", with: "-")).\(ext)"
        panel.directoryURL = AppSettings.defaultSaveFolder

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try fileData.write(to: url)

                closeAnnotationWindow()

                if uploadToWebDAV, AppSettings.canUploadToCloud {
                    let fileName = url.lastPathComponent
                    Task { @MainActor in
                        appState.setTrayUploadStatus(.uploading(fileName: fileName))
                        do {
                            let result = try await WebDAVUploader.shared.upload(fileURL: url)
                            let link = result.publicURL ?? result.fileURL.absoluteString
                            UploadHistory.shared.add(result)
                            appState.setTrayUploadStatus(.success(fileName: result.fileName, link: link))
                            NotificationManager.shared.showUploadSuccess(
                                fileName: result.fileName,
                                publicURL: link
                            )
                            copyLinkToClipboard(link)
                        } catch {
                            appState.setTrayUploadStatus(.failed(message: WebDAVUploader.friendlyUploadErrorMessage(error)))
                        }
                    }
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "annotation.error")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }
}
