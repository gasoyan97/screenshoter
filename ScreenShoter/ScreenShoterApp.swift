import SwiftUI
import AppKit

/// Иконка в Dock только когда открыто окно приложения (аннотации, настройки, установка, история). Без окон — только меню в баре.
private func updateDockVisibility() {
    let mainTitles = ["Аннотации", "Установка", "История", "Настройки", "Быстрый оверлей"]
    let hasWindow = NSApp.windows.contains { w in
        w.isVisible && mainTitles.contains(where: { w.title.contains($0) })
    }
    NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
}

/// Вызывать после закрытия окна: проверка с небольшой задержкой, чтобы окно успело исчезнуть из списка.
private func updateDockVisibilityAfterClose() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { updateDockVisibility() }
}

@main
struct ScreenShoterApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("hasCheckedSetup") private var hasCheckedSetup = false

    init() {
        _ = NotificationManager.shared
        _ = SparkleUpdater.controller
    }

    var body: some Scene {
        MenuBarExtra("ScreenShoter", systemImage: "crop") {
            LauncherMenuView(appState: appState, hasCheckedSetup: $hasCheckedSetup)
        }
        .menuBarExtraStyle(.window)

        Window("ScreenShoter — Аннотации", id: "annotation") {
            if let image = appState.capturedImage {
                AnnotationView(image: image, appState: appState)
                    .id(appState.annotationImageId)
                    .onAppear {
                        DispatchQueue.main.async {
                            if let window = NSApp.windows.first(where: { $0.title.contains("Аннотации") }) {
                                window.level = .normal
                                window.collectionBehavior = [.managed, .participatesInCycle]
                            }
                            updateDockVisibility()
                        }
                    }
                    .onDisappear { updateDockVisibilityAfterClose() }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        .commandsRemoved()

        Window("ScreenShoter — Быстрый оверлей", id: "quickOverlay") {
            if let image = appState.capturedImage {
                QuickOverlayView(image: image, appState: appState)
                    .onAppear {
                        DispatchQueue.main.async {
                            if let window = NSApp.windows.first(where: { $0.title.contains("Быстрый оверлей") }) {
                                window.level = .floating
                                window.collectionBehavior = [.managed, .participatesInCycle]
                                window.isMovableByWindowBackground = true
                            }
                            updateDockVisibility()
                        }
                    }
                    .onDisappear { updateDockVisibilityAfterClose() }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 360, height: 200)
        .windowResizability(.contentSize)
        .commandsRemoved()

        Window("Установка", id: "setup") {
            SetupView()
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.title.contains("Установка") }) {
                            window.level = .floating
                            window.collectionBehavior = [.managed, .participatesInCycle]
                            window.isMovableByWindowBackground = true
                        }
                        updateDockVisibility()
                    }
                }
                .onDisappear { updateDockVisibilityAfterClose() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 520)

        Window("История загрузок", id: "history") {
            HistoryView()
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.title.contains("История") }) {
                            window.level = .normal
                            window.collectionBehavior = [.managed, .participatesInCycle]
                            window.isMovableByWindowBackground = true
                        }
                        updateDockVisibility()
                    }
                }
                .onDisappear { updateDockVisibilityAfterClose() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 500)
        
        Window("Настройки", id: "settings") {
            SettingsView()
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.title.contains("Настройки") }) {
                            window.level = .normal
                            window.collectionBehavior = [.managed, .participatesInCycle]
                            window.isMovableByWindowBackground = true
                        }
                        updateDockVisibility()
                    }
                }
                .onDisappear { updateDockVisibilityAfterClose() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 700)
    }
}
