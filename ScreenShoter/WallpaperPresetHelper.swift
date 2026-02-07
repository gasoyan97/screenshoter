import Foundation
import AppKit
import CoreGraphics

/// Готовые фоны для скриншотов (градиенты, текстуры) в стиле CleanShot.
enum WallpaperPreset: String, CaseIterable, Identifiable {
    case none = "Нет"
    case gradientLight = "Градиент светлый"
    case gradientDark = "Градиент тёмный"
    case gradientBlue = "Градиент синий"
    case gradientWarm = "Градиент тёплый"
    case texturePaper = "Текстура бумаги"

    var id: String { rawValue }
}

enum WallpaperPresetHelper {
    /// Генерирует NSImage для пресета заданного размера (в точках; масштаб применяется при рендере).
    static func image(for preset: WallpaperPreset, size: CGSize, scale: CGFloat = 1) -> NSImage? {
        guard preset != .none else { return nil }
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        guard w > 0, h > 0 else { return nil }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return nil }

        let rect = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        switch preset {
        case .none:
            return nil
        case .gradientLight:
            let colors = [NSColor(white: 0.95, alpha: 1).cgColor, NSColor(white: 0.85, alpha: 1).cgColor]
            drawGradient(in: ctx, rect: rect, colors: colors)
        case .gradientDark:
            let colors = [NSColor(white: 0.18, alpha: 1).cgColor, NSColor(white: 0.12, alpha: 1).cgColor]
            drawGradient(in: ctx, rect: rect, colors: colors)
        case .gradientBlue:
            let colors = [
                NSColor(red: 0.4, green: 0.6, blue: 0.95, alpha: 1).cgColor,
                NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1).cgColor
            ]
            drawGradient(in: ctx, rect: rect, colors: colors)
        case .gradientWarm:
            let colors = [
                NSColor(red: 0.98, green: 0.9, blue: 0.8, alpha: 1).cgColor,
                NSColor(red: 0.95, green: 0.75, blue: 0.6, alpha: 1).cgColor
            ]
            drawGradient(in: ctx, rect: rect, colors: colors)
        case .texturePaper:
            ctx.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
            ctx.fill(rect)
            drawPaperTexture(in: ctx, rect: rect)
        }

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func drawGradient(in ctx: CGContext, rect: CGRect, colors: [CGColor]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    private static func drawPaperTexture(in ctx: CGContext, rect: CGRect) {
        ctx.setStrokeColor(NSColor(white: 0.9, alpha: 0.5).cgColor)
        ctx.setLineWidth(0.5)
        let step: CGFloat = 8
        var y = rect.minY
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        var x = rect.minX
        while x <= rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        ctx.strokePath()
    }
}
