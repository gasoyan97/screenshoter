import SwiftUI

struct DrawingItem: Identifiable {
    let id = UUID()
    var type: DrawingType
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat

    enum DrawingType: Hashable {
        case arrow
        case highlight
    }
}

struct AnnotationView: View {
    let image: NSImage
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var drawings: [DrawingItem] = []
    @State private var currentTool: DrawingItem.DrawingType = .arrow
    @State private var currentColor: Color = .green
    @State private var lineWidth: CGFloat = 4
    @State private var uploadToYandex = true
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var imageSize: CGSize = .zero

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            imageView
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach([DrawingItem.DrawingType.arrow, .highlight], id: \.hashValue) { type in
                    Button {
                        currentTool = type
                    } label: {
                        Image(systemName: type == .arrow ? "arrow.right" : "square.dashed")
                            .frame(width: 32, height: 32)
                            .background(currentTool == type ? Color.accentColor : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 4) {
                ForEach(colors, id: \.description) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: currentColor == color ? 2 : 0)
                        )
                        .onTapGesture { currentColor = color }
                }
            }

            Slider(value: $lineWidth, in: 2...12, step: 1)
                .frame(width: 80)

            Button("↶") {
                if !drawings.isEmpty { drawings.removeLast() }
            }
            .buttonStyle(.plain)

            Spacer()

            Toggle("Загрузить на Яндекс.Диск", isOn: $uploadToYandex)
                .toggleStyle(.checkbox)

            Button("Сохранить") { save() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var imageView: some View {
        GeometryReader { geo in
            let scale = imageScale(in: geo.size)
            let size = CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
                    .shadow(radius: 20)

                Canvas { ctx, canvasSize in
                    for item in drawings {
                        drawItem(item, in: ctx, scale: 1)
                    }
                    if let start = dragStart, let current = dragCurrent {
                        drawItem(
                            DrawingItem(type: currentTool, points: [start, current], color: currentColor, lineWidth: lineWidth),
                            in: ctx, scale: 1
                        )
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            let loc = value.location
                            if dragStart == nil {
                                dragStart = loc
                            }
                            dragCurrent = loc
                        }
                        .onEnded { value in
                            let end = value.location
                            if let start = dragStart {
                                drawings.append(DrawingItem(type: currentTool, points: [start, end], color: currentColor, lineWidth: lineWidth))
                            }
                            dragStart = nil
                            dragCurrent = nil
                        }
                )
                .coordinateSpace(name: "canvas")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            imageSize = NSSize(width: image.size.width, height: image.size.height)
        }
    }

    private func imageScale(in size: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(size.width / imageSize.width, size.height / imageSize.height)
    }

    private func drawItem(_ item: DrawingItem, in ctx: GraphicsContext, scale: CGFloat) {
        let pts = item.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        guard pts.count >= 2 else { return }
        let sw = item.lineWidth * scale
        let c = item.color

        switch item.type {
        case .arrow:
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

        case .highlight:
            let rect = CGRect(
                x: min(pts[0].x, pts[1].x),
                y: min(pts[0].y, pts[1].y),
                width: abs(pts[1].x - pts[0].x),
                height: abs(pts[1].y - pts[0].y)
            )
            if rect.width > 2, rect.height > 2 {
                var path = Path(rect)
                ctx.fill(path, with: .color(c.opacity(0.25)))
                ctx.stroke(path, with: .color(c), lineWidth: sw)
            }
        }
    }

    private func save() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let w = Int(image.size.width * scale)
        let h = Int(image.size.height * scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        image.draw(in: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height))

        let s = CGFloat(w) / image.size.width
        for item in drawings {
            let pts = item.points.map { CGPoint(x: $0.x * s, y: CGFloat(h) - $0.y * s) }
            guard pts.count >= 2 else { continue }
            let c = NSColor(item.color)
            let sw = item.lineWidth * s

            switch item.type {
            case .arrow:
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

            case .highlight:
                let rect = NSRect(
                    x: min(pts[0].x, pts[1].x),
                    y: min(pts[0].y, pts[1].y),
                    width: abs(pts[1].x - pts[0].x),
                    height: abs(pts[1].y - pts[0].y)
                )
                if rect.width > 2, rect.height > 2 {
                    c.withAlphaComponent(0.25).setFill()
                    NSBezierPath(rect: rect).fill()
                    c.setStroke()
                    let bp = NSBezierPath(rect: rect)
                    bp.lineWidth = sw
                    bp.stroke()
                }
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot_\(ISO8601DateFormatter().string(from: Date()).prefix(19).replacingOccurrences(of: ":", with: "-")).png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try pngData.write(to: url)

                if uploadToYandex, !(UserDefaults.standard.string(forKey: "yandexToken") ?? "").isEmpty {
                    Task {
                        do {
                            _ = try await YandexUploader.shared.upload(fileURL: url, token: UserDefaults.standard.string(forKey: "yandexToken") ?? "")
                            await MainActor.run {
                                let alert = NSAlert()
                                alert.messageText = "Готово"
                                alert.informativeText = "Сохранено и загружено на Яндекс.Диск"
                                alert.alertStyle = .informational
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }
                        } catch {
                            await MainActor.run {
                                let alert = NSAlert()
                                alert.messageText = "Ошибка загрузки"
                                alert.informativeText = error.localizedDescription
                                alert.alertStyle = .warning
                                alert.runModal()
                            }
                        }
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Сохранено"
                    alert.informativeText = url.path
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Ошибка"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }
}
