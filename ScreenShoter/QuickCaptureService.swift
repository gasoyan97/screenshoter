import Foundation
import AppKit

/// Скриншот без редактирования: сохранение в папку по умолчанию и авто-загрузка в облако.
final class QuickCaptureService {
    static let shared = QuickCaptureService()

    private init() {}

    /// Делает скриншот всего экрана, сохраняет в папку по умолчанию и при включённой опции загружает в WebDAV.
    func captureAndSave(appState: AppState) async {
        await MainActor.run { NSApp.hide(nil) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        do {
            let image = try await ScreenshotService.shared.capture(mode: .full)
            await MainActor.run {
                saveImage(image, appState: appState)
            }
        } catch {
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Сохраняет изображение в папку по умолчанию и при включённой опции загружает в WebDAV. Вызывается из QuickOverlayView.
    /// - Parameter forceUpload: если true, загружает в WebDAV после сохранения независимо от настройки авто-загрузки; если nil — используется AppSettings.autoUploadToWebDAV.
    func saveImage(_ image: NSImage, appState: AppState, forceUpload: Bool? = nil) {
        let format = AppSettings.screenshotFormat
        let ext = format.fileExtension
        let name = "screenshot_\(ISO8601DateFormatter().string(from: Date()).prefix(19).replacingOccurrences(of: ":", with: "-")).\(ext)"
        guard let folder = AppSettings.defaultSaveFolder else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let url = folder.appendingPathComponent(name)

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var finalBitmap = bitmap
        if AppSettings.scaleDownRetina {
            let w = bitmap.pixelsWide
            let h = bitmap.pixelsHigh
            if w >= 2, h >= 2,
               let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w / 2, pixelsHigh: h / 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
                NSGraphicsContext.current?.imageInterpolation = .high
                bitmap.draw(in: NSRect(x: 0, y: 0, width: w / 2, height: h / 2))
                NSGraphicsContext.restoreGraphicsState()
                finalBitmap = small
            }
        }
        let data: Data?
        if format == .jpeg {
            data = finalBitmap.representation(using: .jpeg, properties: [.compressionFactor: AppSettings.compressionLevel.jpegQuality])
        } else {
            data = finalBitmap.representation(using: .png, properties: [:])
        }
        guard let fileData = data else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        do {
            try fileData.write(to: url)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Ошибка сохранения"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            return
        }

        let canUpload = !AppSettings.webdavURL.isEmpty && !AppSettings.webdavUsername.isEmpty && !AppSettings.webdavPassword.isEmpty
        let shouldUpload = (forceUpload ?? AppSettings.autoUploadToWebDAV) && canUpload
        if shouldUpload {
            Task { @MainActor in
                appState.setTrayUploadStatus(.uploading(fileName: name))
                do {
                    let result = try await WebDAVUploader.shared.upload(
                        fileURL: url,
                        username: AppSettings.webdavUsername,
                        password: AppSettings.webdavPassword
                    )
                    UploadHistory.shared.add(result)
                    let link = result.publicURL ?? result.fileURL.absoluteString
                    appState.setTrayUploadStatus(.success(fileName: result.fileName, link: link))
                    NotificationManager.shared.showUploadSuccess(
                        fileName: result.fileName,
                        publicURL: link
                    )
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                    if let url = URL(string: link) {
                        NSPasteboard.general.writeObjects([url as NSURL])
                    }
                } catch {
                    appState.setTrayUploadStatus(.failed(message: WebDAVUploader.friendlyUploadErrorMessage(error)))
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Кодирует изображение в Data (PNG/JPEG по настройкам) для буфера обмена.
    static func imageData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        var finalBitmap = bitmap
        if AppSettings.scaleDownRetina {
            let w = bitmap.pixelsWide
            let h = bitmap.pixelsHigh
            if w >= 2, h >= 2,
               let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w / 2, pixelsHigh: h / 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
                NSGraphicsContext.current?.imageInterpolation = .high
                bitmap.draw(in: NSRect(x: 0, y: 0, width: w / 2, height: h / 2))
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
}
