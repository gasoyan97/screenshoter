import Foundation
import UserNotifications

/// Статус разрешения на уведомления для отображения в UI.
enum NotificationAuthorizationStatus {
    case notDetermined
    case denied
    case authorized
    case provisional
}

final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Запрашивает разрешение на уведомления (показывает системный диалог). Возвращает true, если разрешено.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Текущий статус разрешения (для отображения на экране настроек/установки).
    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
    }

    func showUploadSuccess(fileName: String, publicURL: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.upload_complete")
        content.body = publicURL
        content.subtitle = fileName
        content.sound = .default
        content.userInfo = ["url": publicURL]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        center.add(request)
    }
}
