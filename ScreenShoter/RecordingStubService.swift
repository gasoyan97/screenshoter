import Foundation
import AppKit

/// Заглушка для записи экрана. Показывает уведомление о том, что функция в разработке.
enum RecordingStubService {
    @MainActor
    static func showStub() {
        let alert = NSAlert()
        alert.messageText = String(localized: "stub.recording.title")
        alert.informativeText = String(localized: "stub.recording.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "stub.ok"))
        alert.runModal()
        NSApp.activate(ignoringOtherApps: true)
    }
}
