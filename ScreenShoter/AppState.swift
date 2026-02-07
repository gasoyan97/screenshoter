import SwiftUI
import AppKit

enum TrayUploadStatus: Equatable {
    case idle
    case uploading(fileName: String)
    case success(fileName: String, link: String)
    case failed(message: String)
}

@MainActor
final class AppState: ObservableObject {
    /// Тот же экземпляр, что видит меню в баре — обновления статуса загрузки всегда идут сюда.
    static weak var current: AppState?

    @Published var capturedImage: NSImage?
    @Published var annotationImageId = UUID()
    @Published var showAnnotationWindow = false
    @Published var showSettingsWindow = false
    @Published var trayUploadStatus: TrayUploadStatus = .idle

    /// Обновляет статус загрузки так, чтобы меню в баре его видело; после успеха через 3 с сбрасывает в .idle.
    func setTrayUploadStatus(_ status: TrayUploadStatus) {
        let target = AppState.current ?? self
        target.trayUploadStatus = status
        if case .success = status {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let t = AppState.current ?? self
                if case .success = t.trayUploadStatus { t.trayUploadStatus = .idle }
            }
        }
    }
}
