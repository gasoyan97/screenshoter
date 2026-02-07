import SwiftUI
import AppKit

/// Компактная панель после съёмки: Сохранить / Копировать / Загрузить / Редактировать (без полного окна аннотаций).
struct QuickOverlayView: View {
    let image: NSImage
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private let thumbnailSize: CGFloat = 120

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    QuickCaptureService.shared.saveImage(image, appState: appState)
                    closeOverlay()
                } label: {
                    Label("overlay.save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    if let data = QuickCaptureService.imageData(for: image) {
                        let format = AppSettings.screenshotFormat
                        let type: NSPasteboard.PasteboardType = format == .jpeg ? NSPasteboard.PasteboardType("public.jpeg") : .png
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setData(data, forType: type)
                    }
                    closeOverlay()
                } label: {
                    Label("overlay.copy", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    QuickCaptureService.shared.saveImage(image, appState: appState, forceUpload: true)
                    closeOverlay()
                } label: {
                    Label("overlay.upload", systemImage: "icloud.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(!AppSettings.canUploadToCloud)

                Button {
                    closeOverlay()
                    appState.capturedImage = image
                    appState.annotationImageId = UUID()
                    openWindow(id: "annotation")
                } label: {
                    Label("overlay.edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(width: 180)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func closeOverlay() {
        NSApp.windows.first(where: { $0.title.contains(String(localized: "window.quick_overlay")) })?.close()
        updateDockVisibilityAfterClose()
    }
}

private func updateDockVisibilityAfterClose() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        let mainTitles = [
            String(localized: "window.annotations"),
            String(localized: "window.setup"),
            String(localized: "window.history"),
            String(localized: "window.settings")
        ]
        let hasWindow = NSApp.windows.contains { w in
            w.isVisible && mainTitles.contains(where: { w.title.contains($0) })
        }
        NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
    }
}
