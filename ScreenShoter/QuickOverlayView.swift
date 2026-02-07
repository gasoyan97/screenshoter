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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func closeOverlay() {
        WindowDockHelper.window(for: .quickOverlay)?.close()
        WindowDockHelper.updateDockVisibilityAfterClose()
    }
}
