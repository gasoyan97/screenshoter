import Foundation
import AppKit

/// Получение пути к текущим обоям рабочего стола Mac.
enum MacWallpaperHelper {
    /// Возвращает путь к изображению обоев главного экрана или nil.
    static func currentWallpaperImagePath() -> String? {
        if let url = desktopImageURLForMainScreen() {
            return url.path
        }
        return nil
    }

    /// NSWorkspace.desktopImageURL(for:) есть на macOS 12+.
    private static func desktopImageURLForMainScreen() -> URL? {
        guard let screen = NSScreen.main else { return nil }
        if #available(macOS 12.0, *) {
            return NSWorkspace.shared.desktopImageURL(for: screen)
        }
        return nil
    }
}
