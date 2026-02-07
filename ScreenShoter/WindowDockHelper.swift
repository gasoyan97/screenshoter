import AppKit
import SwiftUI

/// Поиск окон приложения по стабильному идентификатору и управление видимостью иконки в Dock.
enum WindowDockHelper {
    enum WindowID: String, CaseIterable {
        case annotation
        case quickOverlay
        case setup
        case history
        case settings
    }

    private static let idPrefix = "ScreenShoter."

    /// Находит окно по подстроке заголовка, устанавливает идентификатор и возвращает окно. Вызывать из onAppear.
    static func findAndConfigure(id: WindowID, titleContains: String) -> NSWindow? {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.title.contains(titleContains) }) else { return nil }
        w.identifier = NSUserInterfaceItemIdentifier(idPrefix + id.rawValue)
        return w
    }

    /// Находит окно по стабильному идентификатору (после configure).
    static func window(for id: WindowID) -> NSWindow? {
        let raw = idPrefix + id.rawValue
        return NSApp.windows.first { $0.identifier?.rawValue == raw }
    }

    /// Иконка в Dock только когда открыто окно приложения. Без окон — только меню в баре.
    static func updateDockVisibility() {
        let hasWindow = WindowID.allCases.contains { window(for: $0)?.isVisible == true }
        NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
    }

    /// Вызывать после закрытия окна: проверка с задержкой, чтобы окно успело исчезнуть.
    static func updateDockVisibilityAfterClose() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { updateDockVisibility() }
    }
}
