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
        alert.messageText = "Прокручиваемый захват"
        alert.informativeText = "Функция в разработке. В следующей версии можно будет захватывать длинный контент (чаты, код) с автоматической прокруткой и склейкой в одно изображение."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.activate(ignoringOtherApps: true)
    }
}
