import SwiftUI

@main
struct ScrinsjaterApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Scrinsjater", systemImage: "crop") {
            LauncherMenuView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Window("Scrinsjater — Аннотации", id: "annotation") {
            if let image = appState.capturedImage {
                AnnotationView(image: image, appState: appState)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        .commandsRemoved()

        Window("Настройки", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 280)
    }
}
