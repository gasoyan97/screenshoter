import SwiftUI
import AppKit

/// Полноэкранный оверлей с прицелом по центру и выделением области мышью. Возвращает rect в координатах SwiftUI (origin top-left).
struct RegionCaptureView: View {
    let onCancel: () -> Void
    let onSelect: (CGRect) -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?

    private var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture(count: 2) { onCancel() }

                if startPoint == nil {
                    crosshair(size: size)
                }

                if let rect = selectionRect, rect.width > 2, rect.height > 2 {
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .background(Color.white.opacity(0.15))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("screen"))
                    .onChanged { value in
                        if startPoint == nil { startPoint = value.startLocation }
                        currentPoint = value.location
                    }
                    .onEnded { value in
                        if let start = startPoint {
                            let r = CGRect(
                                x: min(start.x, value.location.x),
                                y: min(start.y, value.location.y),
                                width: abs(value.location.x - start.x),
                                height: abs(value.location.y - start.y)
                            )
                            if r.width > 10, r.height > 10 {
                                onSelect(r)
                            } else {
                                onCancel()
                            }
                        }
                        startPoint = nil
                        currentPoint = nil
                    }
            )
            .coordinateSpace(name: "screen")
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
    }

    private func crosshair(size: CGSize) -> some View {
        Group {
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 1, height: 40)
                .position(x: size.width / 2, y: size.height / 2)
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 40, height: 1)
                .position(x: size.width / 2, y: size.height / 2)
            Circle()
                .strokeBorder(Color.white, lineWidth: 1)
                .frame(width: 8, height: 8)
                .position(x: size.width / 2, y: size.height / 2)
        }
    }
}

private final class RegionContinuationHolder {
    var resumed = false
}

/// Конвертирует rect из координат SwiftUI (origin top-left) в Quartz/screencapture -R (origin bottom-left).
private func rectForScreencapture(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
    CGRect(
        x: rect.origin.x,
        y: screenHeight - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
    )
}

/// Помощник: показать окно выбора области и вернуть rect в координатах Quartz (для screencapture -R) или nil при отмене.
func showRegionSelector() async -> CGRect? {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            let holder = RegionContinuationHolder()
            let screenFrame = NSScreen.main?.frame ?? .zero
            let window = NSWindow(
                contentRect: screenFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let contentView = NSHostingView(rootView: RegionCaptureView(
                onCancel: {
                    window.close()
                    if !holder.resumed { holder.resumed = true; continuation.resume(returning: nil) }
                },
                onSelect: { rect in
                    window.close()
                    let quartzRect = rectForScreencapture(rect, screenHeight: screenFrame.height)
                    if !holder.resumed { holder.resumed = true; continuation.resume(returning: quartzRect) }
                }
            ))
            contentView.frame = NSRect(origin: .zero, size: screenFrame.size)
            window.contentView = contentView
            window.setFrame(screenFrame, display: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
