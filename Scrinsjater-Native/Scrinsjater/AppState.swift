import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var capturedImage: NSImage?
    @Published var showAnnotationWindow = false
    @Published var showSettingsWindow = false

    var yandexToken: String { UserDefaults.standard.string(forKey: "yandexToken") ?? "" }
}
