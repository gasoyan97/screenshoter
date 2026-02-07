import Foundation
import AppKit

/// Прокручиваемый захват (scroll capture): захват длинного контента с прокруткой.
/// Долгосрочная фича: требует интеграции с Accessibility API для определения скроллируемой области,
/// пошаговой прокрутки и склейки кадров.
enum ScrollCaptureService {
    /// Запуск прокручиваемого захвата. Пока заглушка: показывает уведомление о том, что функция в разработке.
    @MainActor
    static func startScrollCapture(appState: AppState) async {
        let alert = NSAlert()
        alert.messageText = String(localized: "stub.scroll.title")
        alert.informativeText = String(localized: "stub.scroll.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "stub.ok"))
        alert.runModal()
        NSApp.activate(ignoringOtherApps: true)
    }
}
