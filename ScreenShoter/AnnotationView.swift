import SwiftUI
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins

struct DrawingItem: Identifiable {
    let id = UUID()
    var type: DrawingType
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat

    enum DrawingType: Hashable {
        case arrow
        case highlight
        case blur
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

struct AnnotationView: View {
    let image: NSImage
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var drawings: [DrawingItem] = []
    @State private var currentTool: DrawingItem.DrawingType = .arrow
    @State private var currentColor: Color = .green
    @State private var lineWidth: CGFloat = 4
    @State private var uploadToWebDAV = AppSettings.autoUploadToWebDAV
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var imageSize: CGSize = .zero
    @State private var isPinned = false
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                Divider()
                    .opacity(0.6)
                imageView
            }
            .background(.ultraThinMaterial)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach([DrawingItem.DrawingType.arrow, .highlight, .blur], id: \.hashValue) { type in
                    Button {
                        currentTool = type
                    } label: {
                        Image(systemName: toolIcon(for: type))
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(currentTool == type ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(currentTool == type ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 24)

            if currentTool != .blur {
                HStack(spacing: 6) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.9), lineWidth: currentColor == color ? 2.5 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                            .onTapGesture { currentColor = color }
                    }
                }

                Slider(value: $lineWidth, in: 2...12, step: 1)
                    .frame(width: 90)
            }

            Button {
                if !drawings.isEmpty { drawings.removeLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(drawings.isEmpty)

            Spacer()

            Toggle("Загрузить после сохранения", isOn: $uploadToWebDAV)
                .toggleStyle(.checkbox)

            Button {
                copyToClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .help("Копировать в буфер обмена")

            Button {
                Task {
                    let ok = await OCRService.recognizeAndCopyToClipboard(from: image)
                    await MainActor.run {
                        if !ok {
                            let alert = NSAlert()
                            alert.messageText = "Текст не распознан"
                            alert.informativeText = "Не удалось распознать текст на изображении."
                            alert.alertStyle = .informational
                            alert.runModal()
                        }
                    }
                }
            } label: {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .help("Распознать текст (OCR) и скопировать в буфер")

            Button {
                togglePin()
            } label: {
                Image(systemName: isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .help(isPinned ? "Открепить окно" : "Закрепить поверх всех окон")

            Button("Сохранить") { save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var imageView: some View {
        GeometryReader { geo in
            let scale = imageScale(in: geo.size)
            let viewSize = CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )
            let blurRects = blurRectsInView(viewSize: viewSize)

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
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
                .padding(20)
                .overlay(
                    Canvas { ctx, _ in
                        for item in drawings {
                            drawItem(item.denormalized(to: viewSize), in: ctx)
                        }
                        if let start = dragStart, let current = dragCurrent {
                            drawItem(DrawingItem(type: currentTool, points: [start, current], color: currentColor, lineWidth: lineWidth), in: ctx)
                        }
                    }
                    .frame(width: viewSize.width, height: viewSize.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                let loc = value.location
                                if dragStart == nil { dragStart = loc }
                                dragCurrent = loc
                            }
                            .onEnded { value in
                                if let start = dragStart, viewSize.width > 0, viewSize.height > 0 {
                                    let nStart = CGPoint(x: start.x / viewSize.width, y: start.y / viewSize.height)
                                    let nEnd = CGPoint(x: value.location.x / viewSize.width, y: value.location.y / viewSize.height)
                                    drawings.append(DrawingItem(type: currentTool, points: [nStart, nEnd], color: currentColor, lineWidth: lineWidth))
                                }
                                dragStart = nil
                                dragCurrent = nil
                            }
                    )
                    .coordinateSpace(name: "canvas")
                )
        }
        .onAppear { imageSize = CGSize(width: image.size.width, height: image.size.height) }
    }

    private func imageScale(in size: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(size.width / imageSize.width, size.height / imageSize.height)
    }

    private func blurRectsInView(viewSize: CGSize) -> [CGRect] {
        var rects: [CGRect] = []
        for item in drawings where item.type == .blur {
            let pts = item.points
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

    private func toolIcon(for type: DrawingItem.DrawingType) -> String {
        switch type {
        case .arrow: return "arrow.right"
        case .highlight: return "square.dashed"
        case .blur: return "eye.slash"
        }
    }

    private func drawItem(_ item: DrawingItem, in ctx: GraphicsContext) {
        let pts = item.points
        guard pts.count >= 2 else { return }
        let sw = item.lineWidth
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
                let path = Path(rect)
                ctx.fill(path, with: .color(c.opacity(0.25)))
                ctx.stroke(path, with: .color(c), lineWidth: sw)
            }

        case .blur:
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

        // Сначала рисуем стрелки и подсветки
        for item in drawings {
            let pts: [CGPoint] = item.points.map {
                CGPoint(
                    x: drawOffsetX + $0.x * drawScreenshotRect.width,
                    y: drawOffsetY + drawScreenshotRect.height - $0.y * drawScreenshotRect.height
                )
            }
            guard pts.count >= 2 else { continue }
            let c = NSColor(item.color)
            let sw = item.lineWidth * scale * min(drawScaleX, drawScaleY)

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

            case .blur:
                break
            }
        }

        // Размытие — отдельным проходом после стрелок и подсветок (bitmap и CIImage здесь оба с origin внизу слева)
        NSGraphicsContext.current?.flushGraphics()
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        if let baseCGImage = bitmap.cgImage {
            for item in drawings where item.type == .blur {
                let pts: [CGPoint] = item.points.map {
                    CGPoint(
                        x: drawOffsetX + $0.x * drawScreenshotRect.width,
                        y: drawOffsetY + drawScreenshotRect.height - $0.y * drawScreenshotRect.height
                    )
                }
                guard pts.count >= 2 else { continue }
                var rect = NSRect(
                    x: min(pts[0].x, pts[1].x),
                    y: min(pts[0].y, pts[1].y),
                    width: abs(pts[1].x - pts[0].x),
                    height: abs(pts[1].y - pts[0].y)
                )
                let boundsW = CGFloat(outW)
                let boundsH = CGFloat(outH)
                rect.origin.x = max(0, min(rect.minX, boundsW - 1))
                rect.origin.y = max(0, min(rect.minY, boundsH - 1))
                rect.size.width = min(rect.width, boundsW - rect.minX)
                rect.size.height = min(rect.height, boundsH - rect.minY)
                guard rect.width > 2, rect.height > 2 else { continue }
                let cropRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
                let ciImage = CIImage(cgImage: baseCGImage)
                let cropped = ciImage.cropped(to: cropRect)
                let blurFilter = CIFilter.gaussianBlur()
                blurFilter.inputImage = cropped
                blurFilter.radius = 28
                guard let outputImage = blurFilter.outputImage else { continue }
                let extent = outputImage.extent
                let centerRect = CGRect(
                    x: extent.midX - rect.width / 2,
                    y: extent.midY - rect.height / 2,
                    width: rect.width,
                    height: rect.height
                )
                guard let blurredCGImage = ciContext.createCGImage(outputImage, from: centerRect) else { continue }
                // Рисуем размытый фрагмент через CGContext в том же координатном пространстве, что и bitmap (origin внизу слева)
                if let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.draw(blurredCGImage, in: rect)
                }
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
            NSApp.windows.first(where: { $0.title.contains("Аннотации") })?.close()
        }
    }

    private func togglePin() {
        guard let window = NSApp.windows.first(where: { $0.title.contains("Аннотации") }) else { return }
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
                alert.messageText = "Ошибка"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }
}
